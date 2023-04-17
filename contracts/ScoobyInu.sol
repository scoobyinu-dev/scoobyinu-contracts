// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IRouter {
    function WETH() external view returns (address);
    function factory() external view returns (address);
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

interface IFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

contract ScoobyInu is ERC20, Ownable {
    using SafeMath for uint256;

    address public swapPair;
    IRouter public immutable router;
    address public constant zeroAddr = address(0);
    address public constant deadAddr = address(0xdead);

    bool swapping;

    address public marketing;

    uint256 private _firstLiquidityBlock;

    uint256 supply = 420 * 1e3 * 1e9 * 1e18;
    uint256 transferTaxAt = supply * 5 / 10000;

    uint256 public buyTax = 10;
    uint256 public sellTax = 10;
    mapping(address => bool) private _isExcludedFromTax;

    constructor(IRouter router_, address marketing_) ERC20("ScoobyDooInu", "Scooby") {
        router = router_;
        address swapPair_ = IFactory(router.factory()).createPair(address(this), router.WETH());
        swapPair = swapPair_;
        marketing = marketing_;

        buyTax = 15;
        sellTax = 17;

        excludeFromTax(marketing, true);
        excludeFromTax(owner(), true);
        excludeFromTax(address(this), true);
        excludeFromTax(deadAddr, true);

        _approve(address(this), address(router), ~uint256(0));

        _mint(owner(), supply);
    }

    receive() external payable {

    }

    function updateTax(uint256 _buyTax, uint256 _sellTax) external onlyOwner {
        require(_buyTax <= 20 && _sellTax <= 20, "too high");
        buyTax = _buyTax;
        sellTax = _sellTax;
    }

    function excludeFromTax(address account, bool isExcluded) public onlyOwner {
        _isExcludedFromTax[account] = isExcluded;
    }

    function isExcludedFromTax(address account) public view returns (bool) {
        return _isExcludedFromTax[account];
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        require(from != zeroAddr, "ERC20: transfer from the zero address");
        require(to != zeroAddr, "ERC20: transfer to the zero address");

        if (amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        if (_firstLiquidityBlock == 0 && to == swapPair) {
            _firstLiquidityBlock = block.number;
        } else if (_firstLiquidityBlock > 0 && block.number > (_firstLiquidityBlock + 3)) {
            buyTax = 10;
            sellTax = 10;
        }

        uint256 contractBalance = balanceOf(address(this));

        bool canSwap = contractBalance >= transferTaxAt;

        if (
            canSwap &&
            from != swapPair &&
            !swapping &&
            !_isExcludedFromTax[from] &&
            !_isExcludedFromTax[to]
        ) {
            swapping = true;
            _swapAndTransfer(contractBalance);
            swapping = false;
        }

        bool takeTax = true;

        if (_isExcludedFromTax[from] || _isExcludedFromTax[to]) {
            takeTax = false;
        }

        uint256 tax = 0;

        if (takeTax) {
            // on sell
            if (to == swapPair) {
                tax = amount.mul(sellTax).div(100);
            }
            // on buy
            else if (from == swapPair) {
                tax = amount.mul(buyTax).div(100);
            }

            if (tax > 0) {
                super._transfer(from, address(this), tax);
                amount = amount.sub(tax);
            }
        }

        super._transfer(from, to, amount);
    }

    function _swapAndTransfer(uint256 amount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amount,
            0,
            path,
            marketing,
            block.timestamp
        );
    }
}