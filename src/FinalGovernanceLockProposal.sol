// SPDX-License-Identifier: WTFPL
pragma solidity 0.8.36;

// forge-lint: disable-next-line(multi-contract-file)
interface ITornadoVault {
    function withdrawTorn(address recipient, uint256 amount) external;
}

/**
 * @notice Terminal Tornado Cash governance implementation: only `unlockAll()` and `lockedBalance()`
 * survives, everything else reverts.
 */
// forge-lint: disable-next-line(multi-contract-file)
contract SealedGovernance {
    address private constant _TORNADO_VAULT = 0x2F50508a8a3D323B91336FA3eA6ae50E55f32185;
    error InsufficientLockedBalance();
    error TornadoCashGovernanceIsDead();

    // The `lockedBalance` mapping is stored at slot 59 (see https://etherscan.io/address/0x5efda50f22d34F262c29268506C5Fa42cB56A1Ce).
    // forge-lint: disable-next-line(unused-state-variables)
    uint256[59] private _gap;
    mapping(address account => uint256 balance) public lockedBalance;

    /**
     * @notice Withdraw the caller's entire locked TORN balance via the vault.
     */
    function unlockAll() external {
        uint256 balance = lockedBalance[msg.sender];
        if (balance == 0) revert InsufficientLockedBalance();
        lockedBalance[msg.sender] = 0;
        ITornadoVault(_TORNADO_VAULT).withdrawTorn(msg.sender, balance);
    }

    /**
     * @dev Catches `propose`, `lock`, `castVote`, `execute`, and everything else.
     */
    fallback() external payable {
        revert TornadoCashGovernanceIsDead();
    }

    receive() external payable {
        revert TornadoCashGovernanceIsDead();
    }
}

// forge-lint: disable-next-line(multi-contract-file)
interface ITransparentUpgradeableProxy {
    function upgradeTo(address newImplementation) external;
    function changeAdmin(address newAdmin) external;
}

/**
 * @notice One-shot governance proposal that permanently disables Tornado Cash governance.
 */
// forge-lint: disable-next-line(multi-contract-file)
contract FinalGovernanceLockProposal {
    address public constant GOVERNANCE_PROXY = 0x5efda50f22d34F262c29268506C5Fa42cB56A1Ce;
    address public constant DEAD_ADMIN = 0x000000000000000000000000000000000000dEaD;

    bytes32 private constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 private constant _ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    address public immutable SEALED_IMPLEMENTATION;

    constructor() {
        SEALED_IMPLEMENTATION = address(new SealedGovernance{salt: keccak256("TORNADO CASH GOVERNANCE IS DEAD!")}());
        // Invariant check: the implementation must be the `SealedGovernance` runtime code.
        assert(SEALED_IMPLEMENTATION.codehash == keccak256(type(SealedGovernance).runtimeCode));
    }

    /**
     * @notice Delegatecalled by `Governance.execute()`: upgrades the proxy to `SealedGovernance`,
     * burns the proxy admin, then verifies both took effect before returning.
     */
    function executeProposal() external {
        ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(GOVERNANCE_PROXY);
        proxy.upgradeTo(SEALED_IMPLEMENTATION);
        proxy.changeAdmin(DEAD_ADMIN);

        // Post-conditions: verify the implementation and admin slots were correctly updated.
        address implSet;
        // forge-lint: disable-next-line(inline-assembly)
        assembly {
            implSet := sload(_IMPLEMENTATION_SLOT)
        }
        // forge-lint: disable-next-line(uninitialized-local)
        assert(implSet == SEALED_IMPLEMENTATION);

        address adminSet;
        // forge-lint: disable-next-line(inline-assembly)
        assembly {
            adminSet := sload(_ADMIN_SLOT)
        }
        // forge-lint: disable-next-line(uninitialized-local)
        assert(adminSet == DEAD_ADMIN);

        // Canary: the proxy must now reject any (static)call (except `unlockAll()` and `lockedBalance()`)
        // with `SealedGovernance`'s error.
        (
            bool staticcallSucceeded,
            bytes memory returnData
            // forge-lint: disable-next-line(low-level-calls)
        ) = GOVERNANCE_PROXY.staticcall(abi.encodeWithSignature("QUORUM_VOTES()"));
        assert(!staticcallSucceeded);
        // forge-lint: disable-next-line(unsafe-typecast)
        assert(bytes4(returnData) == SealedGovernance.TornadoCashGovernanceIsDead.selector);
    }
}
