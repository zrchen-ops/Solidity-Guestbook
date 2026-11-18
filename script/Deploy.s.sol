// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Guestbook} from "../src/Guestbook.sol";

contract DeployScript is Script {
    function run() external returns (Guestbook) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        Guestbook guestbook = new Guestbook();
        console.log("Guestbook deployed at:", address(guestbook));

        vm.stopBroadcast();
        return guestbook;
    }
}
