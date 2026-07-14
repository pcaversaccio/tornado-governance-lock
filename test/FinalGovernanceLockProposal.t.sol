// SPDX-License-Identifier: WTFPL
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {SealedGovernance, FinalGovernanceLockProposal} from "../src/FinalGovernanceLockProposal.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

interface ITORN {
    function nonces(address owner) external view returns (uint256);
}

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
    function unlockAll() external;
    function lockedBalance(address account) external view returns (uint256);
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

    IGovernance private _gov = IGovernance(_GOVERNANCE_PROXY);
    uint256 private _forkId;
    address private _finalGovernanceLockProposalAddr;
    address private _sealedGovernanceAddr;

    function setUp() external {
        _forkId = vm.createSelectFork("https://ethereum-rpc.publicnode.com");
        _finalGovernanceLockProposalAddr = address(new FinalGovernanceLockProposal());
        _sealedGovernanceAddr = vm.computeCreate2Address(
            _SALT, keccak256(type(SealedGovernance).creationCode), _finalGovernanceLockProposalAddr
        );
    }

    function testInitialSetup() external view {
        assertEq(vm.activeFork(), _forkId);
        assertEq(_sealedGovernanceAddr.codehash, keccak256(type(SealedGovernance).runtimeCode));
    }

    function testFinalGovernanceLockProposal() external {
        assertEq(vm.activeFork(), _forkId);
        (address proposer, uint256 key) = makeAddrAndKey("proposer");
        deal(_TORN, proposer, _gov.QUORUM_VOTES());
        uint256 amount = _gov.QUORUM_VOTES();
        uint256 nonce = ITORN(_TORN).nonces(proposer);
        uint256 deadline = block.timestamp + 100_000;
        bytes32 domainSeparator = vm.load(_TORN, bytes32(keccak256(abi.encode(uint256(1), uint256(7)))));
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
        // Lock the proposer's TORN to meet the quorum requirement for the proposal.
        _gov.lock(proposer, amount, deadline, v, r, s);
        // Propose the final governance lock proposal, vote for it, and execute it.
        uint256 proposalId = _gov.propose(_finalGovernanceLockProposalAddr, "TORNADO CASH GOVERNANCE IS DEAD!");
        vm.warp(block.timestamp + _gov.VOTING_DELAY() + uint256(1));
        _gov.castVote(proposalId, true);
        vm.warp(block.timestamp + _gov.VOTING_PERIOD() + _gov.EXECUTION_DELAY() + uint256(1));
        _gov.execute(proposalId);
        vm.stopPrank();

        // Post-conditions: verify the implementation and admin slots were correctly updated.
        assertEq(address(uint160(uint256(vm.load(_GOVERNANCE_PROXY, _IMPLEMENTATION_SLOT)))), _sealedGovernanceAddr);
        assertEq(address(uint160(uint256(vm.load(_GOVERNANCE_PROXY, _ADMIN_SLOT)))), _DEAD_ADMIN);

        // Canary: the proxy must now reject any (static)call (except `unlockAll()` and `lockedBalance()`).
        vm.startPrank(proposer);
        vm.expectRevert(
            abi.encodeWithSelector(SealedGovernance.TornadoCashGovernanceIsDead.selector), _GOVERNANCE_PROXY
        );
        _gov.unlock(uint256(1));
        deal(proposer, 1 wei);
        (bool ok, bytes memory returnData) = _GOVERNANCE_PROXY.call{value: 1 wei}("");
        assertTrue(!ok);
        assertEq(returnData, abi.encodeWithSelector(SealedGovernance.TornadoCashGovernanceIsDead.selector));

        // The proposer should still be able to unlock their TORN after the governance has been locked.
        assertEq(_gov.lockedBalance(proposer), amount);
        _gov.unlockAll();
        assertEq(IERC20(_TORN).balanceOf(proposer), amount);
        assertEq(_gov.lockedBalance(proposer), uint256(0));
        vm.stopPrank();
    }
}
