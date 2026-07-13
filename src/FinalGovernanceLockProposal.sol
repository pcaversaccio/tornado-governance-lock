// SPDX-License-Identifier: WTFPL
pragma solidity 0.8.36;

contract SealedGovernance {
    error TornadoCashGovernanceIsDead();

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

        (bool proposeSucceeded,) =
            GOVERNANCE_PROXY.call(abi.encodeWithSignature("propose(address,string)", address(this), "Canary Proposal"));
        assert(!proposeSucceeded);
    }
}
