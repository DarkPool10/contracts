// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./DarkPool.sol";

contract DarkPoolFactory {
    // Mapping from token pair (tokenA, tokenB) to the DarkPool address
    mapping(bytes32 => address) private tokenPairToPool;

    event DarkPoolCreated(address indexed user, address darkPool, address tokenA, address tokenB);

    /**
     * @dev Creates a new DarkPool contract for a pair of tokens if it doesn't already exist
     * @param tokenA The address of the first token in the pool
     * @param tokenB The address of the second token in the pool
     * @return poolAddress The address of the DarkPool contract for the pair
     */
    function createDarkPool(address tokenA, address tokenB) external returns (address poolAddress) {
        require(tokenA != tokenB, "Tokens must be different");

        // Normalize token order to ensure (tokenA, tokenB) and (tokenB, tokenA) map to the same pool
        (address token1, address token2) = _sortTokens(tokenA, tokenB);

        // Generate a unique key for the token pair
        bytes32 pairKey = keccak256(abi.encodePacked(token1, token2));

        // Check if the pool already exists for this token pair
        poolAddress = tokenPairToPool[pairKey];
        require(poolAddress == address(0), "Pool already exists for this token pair");

        // If the pool doesn't exist, create a new one
        DarkPoolV3 pool = new DarkPoolV3(token1, token2);
        poolAddress = address(pool);

        // Store the newly created pool in the mapping
        tokenPairToPool[pairKey] = poolAddress;

        // Emit event
        emit DarkPoolCreated(msg.sender, poolAddress, token1, token2);
    }

    /**
     * @dev Retrieves the DarkPool for a given token pair
     * @param tokenA The address of the first token
     * @param tokenB The address of the second token
     * @return poolAddress The address of the DarkPool for the token pair
     */
    function getDarkPool(address tokenA, address tokenB) external view returns (address poolAddress) {
        (address token1, address token2) = _sortTokens(tokenA, tokenB);
        bytes32 pairKey = keccak256(abi.encodePacked(token1, token2));
        return tokenPairToPool[pairKey];
    }

    /**
     * @dev Internal function to sort the token addresses to ensure consistency in token pair keys
     * @param tokenA The address of the first token
     * @param tokenB The address of the second token
     * @return token1 The sorted address of the first token
     * @return token2 The sorted address of the second token
     */
    function _sortTokens(address tokenA, address tokenB) internal pure returns (address token1, address token2) {
        return (tokenA < tokenB) ? (tokenA, tokenB) : (tokenB, tokenA);
    }
}
