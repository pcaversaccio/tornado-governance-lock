// SPDX-License-Identifier: WTFPL
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {SealedGovernance, FinalGovernanceLockProposal} from "../src/FinalGovernanceLockProposal.sol";

interface IGovernance {
    function EXECUTION_DELAY() external view returns (uint256);
    function QUORUM_VOTES() external view returns (uint256);
    function VOTING_DELAY() external view returns (uint256);
    function VOTING_PERIOD() external view returns (uint256);
    function lock(address owner, uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;
    function unlock(uint256 amount) external;
    function propose(address target, string memory description) external returns (uint256);
    function castVote(uint256 proposalId, bool support) external;
    function execute(uint256 proposalId) external;
}

interface ITORN {
    function nonces(address owner) external view returns (uint256);
}

contract FinalGovernanceLockProposalTest is Test {
    bytes32 private constant _PERMIT_TYPE_HASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 private constant _SALT = keccak256("TORNADO CASH GOVERNANCE IS DEAD!");
    address private constant _TORN = 0x77777FeDdddFfC19Ff86DB637967013e6C6A116C;
    address private constant _GOVERNANCE_PROXY = 0x5efda50f22d34F262c29268506C5Fa42cB56A1Ce;
    address private constant _DEAD_ADMIN = 0x000000000000000000000000000000000000dEaD;
    bytes32 private constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 private constant _ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    FinalGovernanceLockProposal private finalGovernanceLockProposal;
    address private finalGovernanceLockProposalAddr;
    address private sealedGovernanceAddr;

    function setUp() external {
        vm.createSelectFork("https://ethereum-rpc.publicnode.com");
        finalGovernanceLockProposal = new FinalGovernanceLockProposal();
        finalGovernanceLockProposalAddr = address(finalGovernanceLockProposal);
        sealedGovernanceAddr = vm.computeCreate2Address(
            _SALT, keccak256(type(SealedGovernance).creationCode), finalGovernanceLockProposalAddr
        );
    }

    function testInitialSetup() external view {
        assertEq(sealedGovernanceAddr.codehash, keccak256(type(SealedGovernance).runtimeCode));
    }

    function testFinalGovernanceLockProposal() external {
        (address proposer, uint256 key) = makeAddrAndKey("proposer");
        deal(_TORN, proposer, IGovernance(_GOVERNANCE_PROXY).QUORUM_VOTES());
        uint256 amount = IGovernance(_GOVERNANCE_PROXY).QUORUM_VOTES();
        uint256 nonce = ITORN(_TORN).nonces(proposer);
        uint256 deadline = block.timestamp + 100_000;
        bytes32 domainSeparator = vm.load(_TORN, bytes32(keccak256(abi.encode(uint256(1), 7))));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            key,
            keccak256(
                abi.encodePacked(
                    hex"1901",
                    domainSeparator,
                    keccak256(abi.encode(_PERMIT_TYPE_HASH, proposer, _GOVERNANCE_PROXY, amount, nonce, deadline))
                )
            )
        );

        vm.startPrank(proposer);
        IGovernance(_GOVERNANCE_PROXY).lock(proposer, amount, deadline, v, r, s);
        uint256 proposalId =
            IGovernance(_GOVERNANCE_PROXY).propose(finalGovernanceLockProposalAddr, "TORNADO CASH GOVERNANCE IS DEAD!");
        vm.warp(block.timestamp + IGovernance(_GOVERNANCE_PROXY).VOTING_DELAY() + 1);
        IGovernance(_GOVERNANCE_PROXY).castVote(proposalId, true);
        vm.warp(
            block.timestamp + IGovernance(_GOVERNANCE_PROXY).VOTING_PERIOD()
                + IGovernance(_GOVERNANCE_PROXY).EXECUTION_DELAY() + 1
        );
        IGovernance(_GOVERNANCE_PROXY).execute(proposalId);
        vm.stopPrank();

        address implAfter = address(uint160(uint256(vm.load(_GOVERNANCE_PROXY, _IMPLEMENTATION_SLOT))));
        assertEq(implAfter, sealedGovernanceAddr);

        address adminAfter = address(uint160(uint256(vm.load(_GOVERNANCE_PROXY, _ADMIN_SLOT))));
        assertEq(adminAfter, _DEAD_ADMIN);

        bytes memory expectedErr = abi.encodeWithSelector(SealedGovernance.TornadoCashGovernanceIsDead.selector);
        vm.expectRevert(expectedErr, _GOVERNANCE_PROXY);
        vm.startPrank(proposer);
        IGovernance(_GOVERNANCE_PROXY).unlock(1);
        deal(proposer, 1 wei);
        (bool ok, bytes memory returnData) = _GOVERNANCE_PROXY.call{value: 1 wei}("");
        assertTrue(!ok);
        assertEq(returnData, expectedErr);
        vm.stopPrank();
    }
}
