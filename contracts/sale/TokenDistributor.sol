pragma solidity ^0.4.23;

import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/SafeERC20.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "contracts/utils/BlockTimeMs.sol";
import "./Product.sol";

contract TokenDistributor is ExtendsOwnable {

    using SafeMath for uint256;
    using BlockTimeMs for uint256;
    using SafeERC20 for ERC20;

    struct Purchased {
        address buyer;
        address product;
        uint256 id;
        uint256 amount;
        uint256 etherAmount;
        bool release;
        bool refund;
    }

    ERC20 token;
    Purchased[] private purchasedList;
    uint256 private index;
    uint256 public criterionTime;

    modifier validAddress(address _account) {
        require(_account != address(0));
        require(_account != address(this));
        _;
    }

    event Receipt(
        address buyer,
        address product,
        uint256 id,
        uint256 amount,
        uint256 etherAmount,
        bool release,
        bool refund
    );

    event ReleaseByCount(
        address product,
        uint256 request,
        uint256 succeed,
        uint256 remainder
    );

    event BuyerAddressTransfer(uint256 _id, address _from, address _to, uint256 _etherAmount);

    event WithdrawToken(address to, uint256 amount);

    constructor() public {
        index = 0;
        criterionTime = 0;

        //for error check
        purchasedList.push(Purchased(0, 0, 0, 0, 0, true, true));
    }

    function setToken(address _token) external onlyOwner validAddress(_token) {
        token = ERC20(_token);
    }

    function addPurchased(address _buyer, address _product, uint256 _amount, uint256 _etherAmount)
        external
        onlyOwner
        validAddress(_buyer)
        validAddress(_product)
        returns(uint256)
    {
        index = index.add(1);
        purchasedList.push(Purchased(_buyer, _product, index, _amount, _etherAmount, false, false));

        emit Receipt(_buyer, _product, index, _amount, _etherAmount, false, false);
        return index;
    }

    function getTokenAddress() external view returns(address) {
        return address(token);
    }

    function getAmount(uint256 _index) external view returns(uint256) {
        if (_index == 0) {
            return 0;
        }

        if (purchasedList[_index].release || purchasedList[_index].refund) {
            return 0;
        } else {
            return purchasedList[_index].amount;
        }
    }

    function getEtherAmount(uint256 _index) external view returns(uint256) {
        if (_index == 0) {
            return 0;
        }

        if (purchasedList[_index].release || purchasedList[_index].refund) {
            return 0;
        } else {
            return purchasedList[_index].etherAmount;
        }
    }

    function getAllReceipt()
        external
        view
        onlyOwner
        returns(address[], address[], uint256[], uint256[], uint256[], bool[], bool[])
    {
        address[] memory product = new address[](purchasedList.length.sub(1));
        address[] memory buyer = new address[](purchasedList.length.sub(1));
        uint256[] memory id = new uint256[](purchasedList.length.sub(1));
        uint256[] memory amount = new uint256[](purchasedList.length.sub(1));
        uint256[] memory etherAmount = new uint256[](purchasedList.length.sub(1));
        bool[] memory release = new bool[](purchasedList.length.sub(1));
        bool[] memory refund = new bool[](purchasedList.length.sub(1));

        uint256 receiptIndex = 0;
        for(uint i=1; i < purchasedList.length; i++) {
            product[receiptIndex] = purchasedList[i].product;
            buyer[receiptIndex] = purchasedList[i].buyer;
            id[receiptIndex] = purchasedList[i].id;
            amount[receiptIndex] = purchasedList[i].amount;
            etherAmount[receiptIndex] = purchasedList[i].etherAmount;
            release[receiptIndex] = purchasedList[i].release;
            refund[receiptIndex] = purchasedList[i].refund;

            receiptIndex = receiptIndex.add(1);
        }
        return (product, buyer, id, amount, etherAmount, release, refund);

    }

    function getBuyerReceipt(address _buyer)
        external
        view
        validAddress(_buyer)
        returns(address[], uint256[], uint256[], uint256[], bool[], bool[])
    {
        uint256 count = 0;
        for(uint i=1; i < purchasedList.length; i++) {
            if (purchasedList[i].buyer == _buyer) {
                count = count.add(1);
            }
        }

        address[] memory product = new address[](count);
        uint256[] memory id = new uint256[](count);
        uint256[] memory amount = new uint256[](count);
        uint256[] memory etherAmount = new uint256[](count);
        bool[] memory release = new bool[](count);
        bool[] memory refund = new bool[](count);

        if (count == 0) {
            return (product, id, amount, etherAmount, release, refund);
        }

        count = 0;
        for(i = 1; i < purchasedList.length; i++) {
            if (purchasedList[i].buyer == _buyer) {
                product[count] = purchasedList[i].product;
                id[count] = purchasedList[i].id;
                amount[count] = purchasedList[i].amount;
                etherAmount[count] = purchasedList[i].etherAmount;
                release[count] = purchasedList[i].release;
                refund[count] = purchasedList[i].refund;

                count = count.add(1);
            }
        }
        return (product, id, amount, etherAmount, release, refund);
    }

    function setCriterionTime(uint256 _criterionTime) external onlyOwner {
        require(_criterionTime > 0);

        criterionTime = _criterionTime;
    }

    function releaseByCount(address _product, uint256 _count)
        external
        onlyOwner
    {
        require(criterionTime != 0);
        require(address(token) != address(0));

        uint256 succeed = 0;
        uint256 remainder = 0;

        for(uint i=1; i < purchasedList.length; i++) {
            if (isLive(i) && (purchasedList[i].product == _product)) {
                if (succeed < _count) {
                    Product product = Product(purchasedList[i].product);
                    uint256 oneDay = uint256(1 days).getMs();
                    require(block.timestamp.getMs() >= criterionTime.add(product.lockup().mul(oneDay)));
                    require(token.balanceOf(address(this)) >= purchasedList[i].amount);

                    purchasedList[i].release = true;
                    token.safeTransfer(purchasedList[i].buyer, purchasedList[i].amount);

                    succeed = succeed.add(1);

                    emit Receipt(
                        purchasedList[i].buyer,
                        purchasedList[i].product,
                        purchasedList[i].id,
                        purchasedList[i].amount,
                        purchasedList[i].etherAmount,
                        purchasedList[i].release,
                        purchasedList[i].refund);
                } else {
                    remainder = remainder.add(1);
                }
            }
        }

        emit ReleaseByCount(_product, _count, succeed, remainder);
    }

    function release(uint256 _index) external onlyOwner {
        require(_index != 0);
        require(criterionTime != 0);
        require(isLive(_index));
        require(address(token) != address(0));

        Product product = Product(purchasedList[_index].product);
        uint256 oneDay = uint256(1 days).getMs();
        require(block.timestamp.getMs() >= criterionTime.add(product.lockup().mul(oneDay)));
        require(token.balanceOf(address(this)) >= purchasedList[_index].amount);

        purchasedList[_index].release = true;
        token.safeTransfer(purchasedList[_index].buyer, purchasedList[_index].amount);

        emit Receipt(
            purchasedList[_index].buyer,
            purchasedList[_index].product,
            purchasedList[_index].id,
            purchasedList[_index].amount,
            purchasedList[_index].etherAmount,
            purchasedList[_index].release,
            purchasedList[_index].refund);
    }

    function refund(uint _index, address _product, address _buyer)
        external
        onlyOwner
        returns (bool, uint256)
    {
        if (isLive(_index)
            && purchasedList[_index].product == _product
            && purchasedList[_index].buyer == _buyer)
        {

            purchasedList[_index].refund = true;

            emit Receipt(
                purchasedList[_index].buyer,
                purchasedList[_index].product,
                purchasedList[_index].id,
                purchasedList[_index].amount,
                purchasedList[_index].etherAmount,
                purchasedList[_index].release,
                purchasedList[_index].refund);

            return (true, purchasedList[_index].etherAmount);
        } else {
            return (false, 0);
        }
    }

    function buyerAddressTransfer(uint256 _index, address _from, address _to)
        external
        onlyOwner
        returns (bool, uint256)
    {
        require(isLive(_index));

        if (purchasedList[_index].buyer == _from) {
            purchasedList[_index].buyer = _to;
            emit BuyerAddressTransfer(_index, _from, _to, purchasedList[_index].etherAmount);
            return (true, purchasedList[_index].etherAmount);
        } else {
            return (false, 0);
        }
    }

    function withdrawToken() external onlyOwner {
        require(address(token) != address(0));
        token.safeTransfer(msg.sender, token.balanceOf(address(this)));
        emit WithdrawToken(msg.sender, token.balanceOf(address(this)));
    }

    function isLive(uint256 _index) private view returns(bool){
        if (!purchasedList[_index].release
            && !purchasedList[_index].refund
            && purchasedList[_index].product != address(0)) {
            return true;
        } else {
            return false;
        }
    }
}
