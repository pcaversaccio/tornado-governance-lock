// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {FinalGovernanceLockProposal} from "../src/FinalGovernanceLockProposal.sol";

contract FinalGovernanceLockProposalTest is Test {

    FinalGovernanceLockProposal private finalGovernanceLockProposal;

    function setUp() public {
        finalGovernanceLockProposal = new FinalGovernanceLockProposal();
    }
}
