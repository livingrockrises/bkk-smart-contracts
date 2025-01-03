// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Ownable } from "solady/src/auth/Ownable.sol";

contract SoladyOwnable is Ownable {
    constructor(address owner) Ownable() {
        _initializeOwner(owner);
    }
}
