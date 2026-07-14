// SPDX-License-Identifier: WTFPL
pragma solidity 0.8.36;

interface ITornadoVault {
    function withdrawTorn(address recipient, uint256 amount) external;
}

contract SealedGovernance {
    address private constant _TORNADO_VAULT = 0x2F50508a8a3D323B91336FA3eA6ae50E55f32185;
    error InsufficientLockedBalance();
    error TornadoCashGovernanceIsDead();

    uint256[59] private _gap;

    mapping(address account => uint256 balance) public lockedBalance;

    function unlockAll() external {
        uint256 balance = lockedBalance[msg.sender];
        if (balance == 0) revert InsufficientLockedBalance();
        lockedBalance[msg.sender] = 0;
        ITornadoVault(_TORNADO_VAULT).withdrawTorn(msg.sender, balance);
    }

    fallback() external payable {
        revert TornadoCashGovernanceIsDead();
    }

    receive() external payable {
        revert TornadoCashGovernanceIsDead();
    }
}

interface ITransparentUpgradeableProxy {
    function upgradeTo(address newImplementation) external;
    function changeAdmin(address newAdmin) external;
}

contract FinalGovernanceLockProposal {
    address public constant GOVERNANCE_PROXY = 0x5efda50f22d34F262c29268506C5Fa42cB56A1Ce;
    address public constant DEAD_ADMIN = 0x000000000000000000000000000000000000dEaD;

    bytes32 private constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 private constant _ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    address public immutable SEALED_IMPLEMENTATION;

    constructor() {
        SEALED_IMPLEMENTATION = address(new SealedGovernance{salt: keccak256("TORNADO CASH GOVERNANCE IS DEAD!")}());
        assert(SEALED_IMPLEMENTATION.codehash == keccak256(type(SealedGovernance).runtimeCode));
    }

    function executeProposal() external {
        ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(GOVERNANCE_PROXY);
        proxy.upgradeTo(SEALED_IMPLEMENTATION);
        proxy.changeAdmin(DEAD_ADMIN);

        address implSet;
        assembly {
            implSet := sload(_IMPLEMENTATION_SLOT)
        }
        assert(implSet == SEALED_IMPLEMENTATION);

        address adminSet;
        assembly {
            adminSet := sload(_ADMIN_SLOT)
        }
        assert(adminSet == DEAD_ADMIN);

        (bool staticcallSucceeded, bytes memory returnData) =
            GOVERNANCE_PROXY.staticcall(abi.encodeWithSignature("QUORUM_VOTES()"));
        assert(!staticcallSucceeded);
        assert(
            keccak256(abi.encode(bytes4(returnData)))
                == keccak256(abi.encode(SealedGovernance.TornadoCashGovernanceIsDead.selector))
        );
    }
}
