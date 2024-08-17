// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

contract DarkPool {
    // Public token addresses
    address public tokenA;
    address public tokenB;

    // Order structure
    struct Order {
        address user;
        uint256 amountIn;
        uint256 amountOut;
        bool isAtoB;
    }

    // Private event for order fulfillment
    event OrderFulfilled(address indexed user, uint256 amountIn, uint256 amountOut, bool isAtoB);

    // Queue for A to B orders
    Order[] private atoBOrders;
    // Queue for B to A orders
    Order[] private btoAOrders;

    constructor(address _tokenA, address _tokenB) {
        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    function submitSwapRequest(uint256 amountIn, uint256 amountOut, bool isAtoB) external {
        require(amountIn > 0, "Amount in must be greater than 0");
        require(amountOut > 0, "Amount out must be greater than 0");

        IERC20 token = isAtoB ? IERC20(tokenA) : IERC20(tokenB);
        require(token.transferFrom(msg.sender, address(this), amountIn), "Transfer failed");

        uint256 leftoverAmount = matchOrder(msg.sender, amountIn, amountOut, isAtoB);

        if (leftoverAmount > 0) {
            Order[] storage orders = isAtoB ? atoBOrders : btoAOrders;
            uint256 leftoverAmountOut = (amountOut * leftoverAmount) / amountIn;
            orders.push(Order(msg.sender, leftoverAmount, leftoverAmountOut, isAtoB));
            sortOrders(orders);
        }
    }

    function matchOrder(address user, uint256 amountIn, uint256 amountOut, bool isAtoB) private returns (uint256) {
        Order[] storage oppositeOrders = isAtoB ? btoAOrders : atoBOrders;
        uint256 remainingAmountIn = amountIn;
        uint256 remainingAmountOut = amountOut;
        uint256 i = 0;

        while (i < oppositeOrders.length && remainingAmountIn > 0) {
            Order storage oppositeOrder = oppositeOrders[i];

            (uint256 executedAmountIn, uint256 executedAmountOut) = calculateExecutionAmounts(
                oppositeOrder.amountOut, oppositeOrder.amountIn, remainingAmountIn, remainingAmountOut
            );

            if (executedAmountIn > 0 && executedAmountOut > 0) {
                // Execute the trade
                IERC20 tokenToUser = isAtoB ? IERC20(tokenB) : IERC20(tokenA);
                IERC20 tokenFromUser = isAtoB ? IERC20(tokenA) : IERC20(tokenB);

                require(tokenToUser.transfer(user, executedAmountOut), "Transfer to user failed");
                require(
                    tokenFromUser.transfer(oppositeOrder.user, executedAmountIn), "Transfer to opposite user failed"
                );

                // Emit events
                emit OrderFulfilled(user, executedAmountIn, executedAmountOut, isAtoB);
                emit OrderFulfilled(oppositeOrder.user, executedAmountOut, executedAmountIn, !isAtoB);

                // Update remaining amounts
                remainingAmountIn -= executedAmountIn;
                remainingAmountOut -= executedAmountOut;

                // Update or remove the opposite order
                if (executedAmountOut == oppositeOrder.amountIn) {
                    removeOrder(oppositeOrders, i);
                } else {
                    oppositeOrder.amountIn -= executedAmountOut;
                    oppositeOrder.amountOut -= executedAmountIn;
                    i++;
                }
            } else {
                i++;
            }
        }

        return remainingAmountIn;
    }

    // Function to remove an order from the queue
    function removeOrder(Order[] storage orders, uint256 index) private {
        require(index < orders.length, "Index out of bounds");
        orders[index] = orders[orders.length - 1];
        orders.pop();
    }

    // Function to sort orders by price ratio (most favorable first)
    function sortOrders(Order[] storage orders) private {
        for (uint256 i = 0; i < orders.length; i++) {
            for (uint256 j = i + 1; j < orders.length; j++) {
                if (getPriceRatio(orders[i]) < getPriceRatio(orders[j])) {
                    Order memory temp = orders[i];
                    orders[i] = orders[j];
                    orders[j] = temp;
                }
            }
        }
    }

    function calculateExecutionAmounts(
        uint256 existingOrderAmountIn,
        uint256 existingOrderAmountOut,
        uint256 newOrderAmountIn,
        uint256 newOrderAmountOut
    ) private pure returns (uint256 executedAmountIn, uint256 executedAmountOut) {
        // Calculate how much of the new order can be filled by the existing order
        if (existingOrderAmountOut * newOrderAmountIn >= existingOrderAmountIn * newOrderAmountOut) {
            // The existing order can fully satisfy the new order
            executedAmountIn = newOrderAmountIn;
            executedAmountOut = (executedAmountIn * existingOrderAmountOut) / existingOrderAmountIn;
        } else {
            // The existing order can only partially satisfy the new order
            executedAmountOut = existingOrderAmountOut;
            executedAmountIn = (executedAmountOut * newOrderAmountIn) / newOrderAmountOut;
        }
    }

    function calculatePriceRatio(uint256 amountIn, uint256 amountOut) private pure returns (uint256) {
        return (amountOut * 1e18) / amountIn;
    }

    // Function to calculate price ratio
    function getPriceRatio(Order memory order) private pure returns (uint256) {
        return (order.amountOut * 1e18) / order.amountIn;
    }

    // Function to get the number of pending orders
    function getPendingOrdersCount(bool isAtoB) external view returns (uint256) {
        return isAtoB ? atoBOrders.length : btoAOrders.length;
    }
}

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
}
