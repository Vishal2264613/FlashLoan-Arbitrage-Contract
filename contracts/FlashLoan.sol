// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.6.6;

// Uniswap interface and library imports
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IUniswapV2Router01.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IERC20.sol";
import "./libraries/UniswapV2Library.sol";
import "./libraries/SafeERC20.sol";
import "hardhat/console.sol";

contract FlashLoan {
    using SafeERC20 for IERC20;
    // Factory and Routing Addresses
    address private constant PANCAKE_FACTORY =
        0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;
    address private constant PANCAKE_ROUTER =
        0x10ED43C718714eb63d5aA57B78B54704E256024E;

    // Token Addresses
    address private constant BUSD = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;
    address private constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address private constant CROX = 0x2c094F5A7D1146BB93850f629501eB749f6Ed491;
    address private constant CAKE = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;

    uint256 private deadline = block.timestamp + 1 days;
    uint256 private constant MAX_INT =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;


    function checkResult(uint _replayAmount,uint _acquiredCoin) pure private returns(bool){
        return _acquiredCoin > _replayAmount;
    }    

    function getBalanceOfToken(address _address) public view returns(uint256){
        return IERC20(_address).balanceOf(address(this));
    }

    function placeTrade(address _fromToken,address _toToken,uint _amountIn) private returns(uint){
        address pair = IUniswapV2Factory(PANCAKE_FACTORY).getPair(
            _fromToken,
            _toToken
        );
        require(pair!=address(0),"pool doesn't exist");

        address[] memory path = new address[](2);
        path[0] = _fromToken;
        path[1] = _toToken;

        uint256 amountRequired = IUniswapV2Router01(PANCAKE_ROUTER)
        .getAmountsOut(_amountIn,path)[1];

        uint256 amountReceived = IUniswapV2Router01(PANCAKE_ROUTER).
        swapExactTokensForTokens(
            _amountIn,
            amountRequired,
            path,
            address(this),
            deadline
        )[1];

        require(amountRequired>0,"Transaction Abort");

        return amountReceived;
    }

    function initiateArbitrage(address _budBorrow, uint _amount) {
        IERC20(BUSD).safeApprove(address(PANCAKE_FACTORY), MAX_INT);
        IERC20(CROX).safeApprove(address(PANCAKE_FACTORY), MAX_INT);
        IERC20(CAKE).safeApprove(address(PANCAKE_FACTORY), MAX_INT);

        address pair = IUniswapV2Factory(PANCAKE_FACTORY).getPair(
            _budBorrow,
            WBNB
        )

        require(pair!=address(0),"pool doesn't exist");

        address token0 = IUniswapV2Pair.(pair).token0;//WBNB
        address token1 = IUniswapV2Pair.(pair).token1;//BUSD

        uint amount0Out = _budBorrow == token0 ? _amount:0;
        uint amount1Out = _budBorrow == token1 ? _amount:0; // BUSD Amount

        bytes memory data = abi.encode(_budBorrow,_amount,msg.sender);
        IUniswapV2Pair(pair).swap(amount0Out,amount1Out,address(this),data);
    }

        function pancakeCall(address _sender,uint _amount0,uint _amount1,bytes calldata _data) external{
            address token0 = IUniswapV2Pair(msg.sender).token0;
            address token1 = IUniswapV2Pair(msg.sender).token1;
            address pair = IUniswapV2Factory(PANCAKE_FACTORY).getPair(
                token0,
                token1
            )

            require(msg.sender==pair,"This sender need to match the pair");
            require(_sender== address(this),"Sender should match the contract");

            (address busdBorrow,uint256 amount,address myAddress)= abi.decode(
                _data,
                (address,uint256,address)
            )

            uint256 fee = ((amount * 3) / 997) + 1;
            uint256 repayAmount = amount + fee;

            uint256 loanAmount = _amount0 > 0 ? _amount0:_amount1;

            uint256 trade1Coin = placeTrade(BUSD,CROX,loanAmount);
            uint256 trade2Coin = placeTrade(CROX,CAKE,trade1Coin);
            uint256 trade3Coin = placeTrade(CAKE,BUSD,trade2Coin);

            bool checkProfit = checkResult(repayAmount,trade3Coin);
            require(checkProfit,"Arbitrage was not profitable");

            IERC20 otherToken = IERC20(BUSD);
            otherToken.transfer(myAddress,trade3Coin-repayAmount);

            IERC20(busdBorrow).transfer(pair,repayAmount);

        }
}
