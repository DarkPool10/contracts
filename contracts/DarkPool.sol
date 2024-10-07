// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract DarkPoolV3 {
    using SafeERC20 for IERC20;

    address public tokenA;
    address public tokenB;

    struct Order {
        address user;
        uint256 amountIn;
        uint256 amountOut;
        uint256 executedAmountIn;
        uint256 executedAmountOut;
        bool isAtoB;
    }

    event OrderFulfilled(address indexed user, uint256 amountIn, uint256 amountOut, bool isAtoB);

    Order[] private atoBOrders;
    Order[] private btoAOrders;
    mapping(address => Order[]) private userOrders;

    constructor(address _tokenA, address _tokenB) {
        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    // -- PUBLIC FUNCTIONS --

    function submitSwapRequest(uint256 amountIn, uint256 minAmountOut, bool isAtoB) external {
        require((amountIn > 0) && (minAmountOut > 0), "amountIn and minAmountOut must be >0");

        IERC20 token = isAtoB ? IERC20(tokenA) : IERC20(tokenB);
        token.safeTransferFrom(msg.sender, address(this), amountIn);

        uint256 leftoverAmountIn;
        uint256 leftoverAmountOut;
        address unfulfilledOrderOwner;

        // Match the current order with the opposite orders (if there are opposite orders)
        if (getPendingOrdersCount(!isAtoB) > 0) {
            (leftoverAmountIn, leftoverAmountOut, unfulfilledOrderOwner) =
                _matchOrder(msg.sender, amountIn, minAmountOut, isAtoB);
        } else {
            leftoverAmountIn = amountIn;
            leftoverAmountOut = minAmountOut;
            unfulfilledOrderOwner = msg.sender;
        }

        // If there's leftover from an order, add the remaining portion back for that user
        if (leftoverAmountIn > 0 && unfulfilledOrderOwner != address(0)) {
            _addOrder(
                unfulfilledOrderOwner,
                amountIn,
                minAmountOut,
                amountIn - leftoverAmountIn,
                minAmountOut - leftoverAmountOut,
                isAtoB
            );
        }
    }

    function getUserOwnOrders() external view returns (Order[] memory) {
        return userOrders[msg.sender];
    }

    // TODO - remove this
    function getPendingOrdersCount(bool isAtoB) public view returns (uint256) {
        return isAtoB ? atoBOrders.length : btoAOrders.length;
    }

    function cancelOrder(uint256 index) external {
        require(index < userOrders[msg.sender].length, "Invalid index");
        Order memory order = userOrders[msg.sender][index];
        Order[] storage orders = order.isAtoB ? atoBOrders : btoAOrders;

        for (uint256 i = 0; i < orders.length; i++) {
            if (
                orders[i].user == msg.sender && orders[i].amountIn == order.amountIn
                    && orders[i].amountOut == order.amountOut && orders[i].isAtoB == order.isAtoB
            ) {
                _removeOrder(orders, i);
                break;
            }
        }

        _removeUserOrder(msg.sender, index);
        IERC20 token = order.isAtoB ? IERC20(tokenA) : IERC20(tokenB);
        token.safeTransfer(msg.sender, order.amountIn);
    }

    // -- INTERNAL FUNCTIONS --

    function _matchOrder(address user, uint256 amountIn, uint256 amountOut, bool isAtoB)
        private
        returns (uint256 remainingAmountIn, uint256 remainingAmountOut, address unfulfilledOrderOwner)
    {
        Order[] storage oppositeOrders = isAtoB ? btoAOrders : atoBOrders;
        remainingAmountIn = amountIn;
        remainingAmountOut = amountOut;
        uint256 i = 0;

        // Initialize the unfulfilled order owner as msg.sender (user submitting the order)
        unfulfilledOrderOwner = user;

        while (i < oppositeOrders.length && remainingAmountIn > 0 && _tradePossible(amountIn, amountOut, isAtoB)) {
            Order storage oppositeOrder;
            if (isAtoB) {
                oppositeOrder = oppositeOrders[oppositeOrders.length - 1 - i];
            } else {
                oppositeOrder = oppositeOrders[i];
            }
            uint256 executedAmountIn;
            uint256 executedAmountOut;

            (executedAmountIn, executedAmountOut) = _calculateExecutionAmounts(
                oppositeOrder.amountOut - oppositeOrder.executedAmountOut,
                oppositeOrder.amountIn - oppositeOrder.executedAmountIn,
                remainingAmountIn,
                remainingAmountOut,
                isAtoB
            );

            if (executedAmountIn > 0 && executedAmountOut > 0) {
                IERC20 tokenToUser = isAtoB ? IERC20(tokenB) : IERC20(tokenA);
                IERC20 tokenFromUser = isAtoB ? IERC20(tokenA) : IERC20(tokenB);

                tokenToUser.safeTransfer(user, executedAmountOut);
                tokenFromUser.safeTransfer(oppositeOrder.user, executedAmountIn);

                emit OrderFulfilled(user, executedAmountIn, executedAmountOut, isAtoB);
                emit OrderFulfilled(oppositeOrder.user, executedAmountOut, executedAmountIn, !isAtoB);

                remainingAmountIn -= executedAmountIn;

                if (executedAmountOut > remainingAmountOut) {
                    remainingAmountOut = 0;
                } else {
                    remainingAmountOut -= executedAmountOut;
                }

                // If the opposite order is fully fulfilled, remove it
                if (oppositeOrder.executedAmountIn + executedAmountOut >= oppositeOrder.amountIn) {
                    // Find the index of the opposite order in userOrders
                    uint256 userOrderIndex = _findUserOrderIndex(
                        oppositeOrder.user, oppositeOrder.amountIn, oppositeOrder.amountOut, oppositeOrder.isAtoB
                    );
                    _removeUserOrder(oppositeOrder.user, userOrderIndex); // Remove from userOrders
                    _removeOrder(oppositeOrders, i);
                } else {
                    // If the opposite order is only partially fulfilled, update it
                    oppositeOrder.executedAmountIn += executedAmountOut;
                    oppositeOrder.executedAmountOut += executedAmountIn;
                    _updateUserOrder(
                        oppositeOrder.user, oppositeOrder.amountIn, oppositeOrder.amountOut, oppositeOrder.isAtoB
                    ); // Update in userOrders
                    i++;

                    // In this case, the opposite order has leftovers, so update unfulfilledOrderOwner
                    unfulfilledOrderOwner = oppositeOrder.user;
                }
            } else {
                i++;
            }
        }

        if (remainingAmountIn > 0) {
            unfulfilledOrderOwner = user;
        }
        return (remainingAmountIn, remainingAmountOut, unfulfilledOrderOwner);
    }

    function _addOrder(
        address user,
        uint256 amountIn,
        uint256 amountOut,
        uint256 executedAmountIn,
        uint256 executedAmountOut,
        bool isAtoB
    ) private {
        Order[] storage orders = isAtoB ? atoBOrders : btoAOrders;
        orders.push(Order(user, amountIn, amountOut, executedAmountIn, executedAmountOut, isAtoB));
        userOrders[user].push(Order(user, amountIn, amountOut, executedAmountIn, executedAmountOut, isAtoB));
        _sortOrders(orders); // Optionally, sort the orders if needed
    }

    function _removeOrder(Order[] storage orders, uint256 index) private {
        require(index < orders.length, "Index out of bounds");
        orders[index] = orders[orders.length - 1];
        orders.pop();
        _sortOrders(orders);
    }

    function getHighestBuyPriceB() public view returns (uint256) {
        if (atoBOrders.length == 0) {
            return 0;
        }
        return _getPriceB(atoBOrders[0]);
    }

    function getLowestSellPriceB() public view returns (uint256) {
        if (btoAOrders.length == 0) {
            return 2 ** 256 - 1;
        }
        return _getPriceB(btoAOrders[btoAOrders.length - 1]);
    }

    function _sortOrders(Order[] storage orders) private {
        // Sorts from HIGH to LOW
        for (uint256 i = 0; i < orders.length; i++) {
            for (uint256 j = i + 1; j < orders.length; j++) {
                if (_getPriceB(orders[i]) < _getPriceB(orders[j])) {
                    Order memory temp = orders[i];
                    orders[i] = orders[j];
                    orders[j] = temp;
                }
            }
        }
    }

    function _calculateExecutionAmounts(
        uint256 existingOrderAmountIn,
        uint256 existingOrderAmountOut,
        uint256 newOrderAmountIn,
        uint256 newOrderAmountOut,
        bool isAtoB
    ) private pure returns (uint256 executedAmountIn, uint256 executedAmountOut) {
        uint256 existingRatio = (existingOrderAmountOut * 1e18) / existingOrderAmountIn;
        uint256 newRatio = (newOrderAmountOut * 1e18) / newOrderAmountIn;

        if (newRatio == existingRatio) {
            executedAmountIn = existingOrderAmountIn;
            executedAmountOut = existingOrderAmountOut;
        } else {
            if (!isAtoB) {
                executedAmountIn = (existingOrderAmountOut * newOrderAmountIn) / newOrderAmountOut;
                executedAmountOut = existingOrderAmountOut;
            } else {
                executedAmountIn = newOrderAmountIn;
                executedAmountOut = (newOrderAmountIn * existingOrderAmountOut) / existingOrderAmountIn;
            }
        }
    }

    function _tradePossible(uint256 amountIn, uint256 amountOut, bool isAtoB) private view returns (bool) {
        uint256 highestBuyPrice = getHighestBuyPriceB();
        uint256 lowestSellPrice = getLowestSellPriceB();

        if (isAtoB) {
            if ((amountIn * 1e18) / amountOut > highestBuyPrice) {
                highestBuyPrice = (amountIn * 1e18) / amountOut;
            }
        } else {
            if ((amountOut * 1e18) / amountIn < lowestSellPrice) {
                lowestSellPrice = (amountOut * 1e18) / amountIn;
            }
        }
        return highestBuyPrice >= lowestSellPrice;
    }

    function _getPriceB(Order memory order) private pure returns (uint256) {
        if (order.isAtoB) {
            return (order.amountIn * 1e18) / order.amountOut;
        } else {
            return (order.amountOut * 1e18) / order.amountIn;
        }
    }

    function _removeUserOrder(address user, uint256 index) private {
        require(index < userOrders[user].length, "Invalid index");
        userOrders[user][index] = userOrders[user][userOrders[user].length - 1]; // Swap with the last order
        userOrders[user].pop(); // Remove the last element
    }

    function _updateUserOrder(address user, uint256 amountIn, uint256 amountOut, bool isAtoB) private {
        Order[] storage orders = userOrders[user];
        for (uint256 i = 0; i < orders.length; i++) {
            if (orders[i].isAtoB == isAtoB) {
                orders[i].executedAmountIn += amountIn;
                orders[i].executedAmountOut += amountOut;
            }
        }
    }

    function _findUserOrderIndex(address user, uint256 amountIn, uint256 amountOut, bool isAtoB)
        private
        view
        returns (uint256)
    {
        Order[] storage orders = userOrders[user];
        for (uint256 i = 0; i < orders.length; i++) {
            if (orders[i].amountIn == amountIn && orders[i].amountOut == amountOut && orders[i].isAtoB == isAtoB) {
                return i;
            }
        }
        revert("Order not found");
    }
}
