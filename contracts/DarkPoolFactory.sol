// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./DarkPool.sol";

contract DarkPoolFactory {
    // user address => list of DarkPools created
    mapping(address => address[]) private userPools;

    event DarkPoolCreated(address indexed user, address darkPool, address tokenA, address tokenB);

    /**
     * @dev Creates a new DarkPool contract for the caller
     * @param tokenA The address of the first token in the pool
     * @param tokenB The address of the second token in the pool
     * @return poolAddress The address of the newly created DarkPool contract
     */
    function createDarkPool(address tokenA, address tokenB) external returns (address poolAddress) {
        DarkPool pool = new DarkPool(tokenA, tokenB);
        poolAddress = address(pool);

        userPools[msg.sender].push(poolAddress);

        emit DarkPoolCreated(msg.sender, poolAddress, tokenA, tokenB);
    }

    /**
     * @dev Retrieves the DarkPools created by the sender
     * @return pools The array of DarkPool contracts created by the sender
     */
    function getPools() external view returns (address[] memory pools) {
        pools = userPools[msg.sender];
    }
}
