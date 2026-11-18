// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC721Market {
    function ownerOf(uint256 tokenId) external view returns (address);
    function transferFrom(address from, address to, uint256 tokenId) external;
}

/// @title PoaMarket V3 — on-site marketplace for Proof of AGI NFTs.
/// Same as V2 (custody listings, 4% fee) plus a floor rule: any list or
/// reprice below MIN_PRICE (0.0022 BNB) burns the NFT to the dead address
/// instead of listing it.
contract PoaMarket {
    IERC721Market public immutable nft;
    address public owner;
    uint256 public feeBps = 400; // 4%
    uint256 public constant MIN_PRICE = 0.0022 ether;
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    struct Listing {
        address seller;
        uint256 price;
    }

    mapping(uint256 => Listing) public listings;
    uint256[] private _listedIds;
    mapping(uint256 => uint256) private _indexOf;

    bool private _locked;

    event Listed(address indexed seller, uint256 indexed tokenId, uint256 price);
    event PriceUpdated(address indexed seller, uint256 indexed tokenId, uint256 price);
    event Sold(address indexed seller, address indexed buyer, uint256 indexed tokenId, uint256 price);
    event Cancelled(address indexed seller, uint256 indexed tokenId);
    event Burned(address indexed seller, uint256 indexed tokenId, uint256 price);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    modifier nonReentrant() {
        require(!_locked, "reentrant");
        _locked = true;
        _;
        _locked = false;
    }

    constructor(address nftAddress, address initialOwner) {
        require(nftAddress != address(0) && initialOwner != address(0), "zero");
        nft = IERC721Market(nftAddress);
        owner = initialOwner;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return 0x150b7a02;
    }

    function listedCount() external view returns (uint256) {
        return _listedIds.length;
    }

    function getListings(uint256 offset, uint256 limit)
        external
        view
        returns (uint256[] memory ids, address[] memory sellers, uint256[] memory prices)
    {
        uint256 total = _listedIds.length;
        if (offset >= total) {
            return (new uint256[](0), new address[](0), new uint256[](0));
        }
        uint256 n = total - offset;
        if (n > limit) n = limit;
        ids = new uint256[](n);
        sellers = new address[](n);
        prices = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            uint256 id = _listedIds[offset + i];
            ids[i] = id;
            sellers[i] = listings[id].seller;
            prices[i] = listings[id].price;
        }
    }

    function list(uint256 tokenId, uint256 price) external {
        require(price > 0, "Price must be > 0");
        Listing storage l = listings[tokenId];
        if (l.seller == msg.sender && l.price > 0) {
            if (price < MIN_PRICE) {
                // Repricing below the floor burns the NFT out of custody.
                _remove(tokenId);
                nft.transferFrom(address(this), BURN_ADDRESS, tokenId);
                emit Burned(msg.sender, tokenId, price);
                return;
            }
            l.price = price; // reprice, NFT already in custody
            emit PriceUpdated(msg.sender, tokenId, price);
            return;
        }
        require(l.seller == address(0), "Already listed");
        require(nft.ownerOf(tokenId) == msg.sender, "Not the owner");
        if (price < MIN_PRICE) {
            // Listing below the floor burns the NFT instead of listing it.
            nft.transferFrom(msg.sender, BURN_ADDRESS, tokenId);
            emit Burned(msg.sender, tokenId, price);
            return;
        }
        listings[tokenId] = Listing({seller: msg.sender, price: price});
        _indexOf[tokenId] = _listedIds.length;
        _listedIds.push(tokenId);
        nft.transferFrom(msg.sender, address(this), tokenId);
        emit Listed(msg.sender, tokenId, price);
    }

    function buy(uint256 tokenId) external payable nonReentrant {
        Listing memory l = listings[tokenId];
        require(l.price > 0, "Not listed");
        require(msg.value >= l.price, "Insufficient payment");
        _remove(tokenId);
        uint256 fee = (l.price * feeBps) / 10000;
        uint256 toSeller = l.price - fee;
        nft.transferFrom(address(this), msg.sender, tokenId);
        (bool ok, ) = payable(l.seller).call{value: toSeller}("");
        require(ok, "Seller payment failed");
        if (fee > 0) {
            (bool ok2, ) = payable(owner).call{value: fee}("");
            require(ok2, "Fee payment failed");
        }
        if (msg.value > l.price) {
            (bool ok3, ) = payable(msg.sender).call{value: msg.value - l.price}("");
            require(ok3, "Refund failed");
        }
        emit Sold(l.seller, msg.sender, tokenId, l.price);
    }

    function cancel(uint256 tokenId) external {
        require(listings[tokenId].seller == msg.sender, "Not the seller");
        _remove(tokenId);
        nft.transferFrom(address(this), msg.sender, tokenId);
        emit Cancelled(msg.sender, tokenId);
    }

    function setFeeBps(uint256 bps) external onlyOwner {
        require(bps <= 1000, "Fee too high");
        feeBps = bps;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero");
        owner = newOwner;
    }

    function _remove(uint256 tokenId) internal {
        uint256 i = _indexOf[tokenId];
        uint256 last = _listedIds[_listedIds.length - 1];
        _listedIds[i] = last;
        _indexOf[last] = i;
        _listedIds.pop();
        delete _indexOf[tokenId];
        delete listings[tokenId];
    }
}
