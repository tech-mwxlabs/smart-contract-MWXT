// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';

contract UUPSUpgradeableProxy is ERC1967Proxy {
    constructor(address implementation, bytes memory _data) payable ERC1967Proxy(implementation, _data) {}
}