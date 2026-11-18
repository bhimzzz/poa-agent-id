// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IAgentRegistryNFT {
    function balanceOf(address account) external view returns (uint256);
}

/// @title Proof of AGI NFT — 2,500 line-eye pieces on BSC.
/// Token IDs 1..2,500 carry pre-shuffled rarity (assigned at generation).
/// Mint is Agent-ID-only (SPACE ID Agent ID registry), phased by mint count:
/// mints #1-1,000 free (max 5 free per wallet), mints #1,001-2,500 cost
/// 0.0015 BNB each (max 10 paid per wallet), proceeds forwarded 100% to owner.
/// Owner (project wallet) is fixed at construction; the deployer keeps a
/// setup-only admin role (setBaseURI / setSaleActive) until lockSetup().
contract PoaNFT {
    string public name = "Proof of AGI";
    string public symbol = "POA";
    uint256 public constant MAX_SUPPLY = 2_500;
    uint256 public constant FREE_LIMIT = 1_000;
    uint256 public constant PRICE = 0.0015 ether;
    uint256 public constant MAX_FREE_PER_WALLET = 5;
    uint256 public constant MAX_PAID_PER_WALLET = 10;
    uint256 public constant MAX_PER_TX = 10;

    address public owner;
    address public admin; // deployer, setup only; zeroed by lockSetup()
    bool public setupLocked;
    bool public saleActive;
    string private _baseTokenURI;
    IAgentRegistryNFT public registry;

    uint256 private _nextId = 1;
    mapping(address => uint256) public freeMintedBy;
    mapping(address => uint256) public paidMintedBy;

    // ERC721 state
    mapping(uint256 => address) private _owners;
    mapping(address => uint256) public balanceOf;
    mapping(uint256 => address) public getApproved;
    mapping(address => mapping(address => bool)) public isApprovedForAll;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner_, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner_, address indexed operator, bool approved);
    event Minted(address indexed buyer, uint256 firstId, uint256 qty, uint256 paidWei);

    constructor(address initialOwner, address registry_) {
        require(initialOwner != address(0), "zero owner");
        owner = initialOwner;
        admin = msg.sender;
        registry = IAgentRegistryNFT(registry_);
    }

    // ---------- views ----------
    function totalSupply() public view returns (uint256) {
        return _nextId - 1;
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address o = _owners[tokenId];
        require(o != address(0), "nonexistent token");
        return o;
    }

    function hasAgentId(address a) public view returns (bool) {
        try registry.balanceOf(a) returns (uint256 b) {
            return b > 0;
        } catch {
            return false;
        }
    }

    function splitFor(uint256 count) public view returns (uint256 freeShares, uint256 paidShares) {
        uint256 minted = totalSupply();
        uint256 freeLeft = minted < FREE_LIMIT ? FREE_LIMIT - minted : 0;
        freeShares = count > freeLeft ? freeLeft : count;
        paidShares = count - freeShares;
    }

    function costFor(uint256 count) public view returns (uint256) {
        (, uint256 paidShares) = splitFor(count);
        return paidShares * PRICE;
    }

    function tokenURI(uint256 tokenId) public view returns (string memory) {
        require(_owners[tokenId] != address(0), "nonexistent token");
        return string(abi.encodePacked(_baseTokenURI, _toString(tokenId), ".json"));
    }

    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return interfaceId == 0x80ac58cd || interfaceId == 0x5b5e139f || interfaceId == 0x01ffc9a7;
    }

    // ---------- mint ----------
    function mint(uint256 count) external payable {
        require(saleActive, "Sale not active");
        require(count >= 1 && count <= MAX_PER_TX, "count 1-10");
        require(hasAgentId(msg.sender), "Agent ID required");
        require(totalSupply() + count <= MAX_SUPPLY, "Sold out");
        (uint256 freeShares, uint256 paidShares) = splitFor(count);
        require(freeMintedBy[msg.sender] + freeShares <= MAX_FREE_PER_WALLET, "max 5 free per wallet");
        require(paidMintedBy[msg.sender] + paidShares <= MAX_PAID_PER_WALLET, "max 10 paid per wallet");
        uint256 cost = paidShares * PRICE;
        require(msg.value >= cost, "insufficient BNB");

        freeMintedBy[msg.sender] += freeShares;
        paidMintedBy[msg.sender] += paidShares;

        uint256 firstId = _nextId;
        for (uint256 i = 0; i < count; i++) {
            uint256 id = _nextId++;
            _owners[id] = msg.sender;
            balanceOf[msg.sender] += 1;
            emit Transfer(address(0), msg.sender, id);
            // safe-mint check for contract recipients
            if (msg.sender.code.length > 0) {
                require(
                    _checkOnERC721Received(address(0), msg.sender, id, ""),
                    "ERC721: transfer to non ERC721Receiver"
                );
            }
        }
        emit Minted(msg.sender, firstId, count, cost);

        if (cost > 0) {
            (bool ok, ) = owner.call{value: cost}("");
            require(ok, "proceeds forward failed");
        }
        if (msg.value > cost) {
            (bool ok2, ) = msg.sender.call{value: msg.value - cost}("");
            require(ok2, "refund failed");
        }
    }

    // ---------- setup / owner ----------
    function setBaseURI(string calldata uri) external {
        require(!setupLocked && (msg.sender == admin || msg.sender == owner), "not admin/owner");
        _baseTokenURI = uri;
    }

    function setSaleActive(bool active) external {
        require(msg.sender == owner || (!setupLocked && msg.sender == admin), "not owner/admin");
        saleActive = active;
    }

    function lockSetup() external {
        require(msg.sender == admin || msg.sender == owner, "not admin/owner");
        setupLocked = true;
        admin = address(0);
    }

    function transferOwnership(address newOwner) external {
        require(msg.sender == owner, "not owner");
        require(newOwner != address(0), "zero");
        owner = newOwner;
    }

    function withdraw() external {
        require(msg.sender == owner, "not owner");
        (bool ok, ) = owner.call{value: address(this).balance}("");
        require(ok, "Withdraw failed");
    }

    // ---------- ERC721 transfers ----------
    function approve(address to, uint256 tokenId) external {
        address o = ownerOf(tokenId);
        require(msg.sender == o || isApprovedForAll[o][msg.sender], "not authorized");
        getApproved[tokenId] = to;
        emit Approval(o, to, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) external {
        isApprovedForAll[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        require(ownerOf(tokenId) == from, "not owner");
        require(
            msg.sender == from || msg.sender == getApproved[tokenId] || isApprovedForAll[from][msg.sender],
            "not authorized"
        );
        require(to != address(0), "zero to");
        getApproved[tokenId] = address(0);
        balanceOf[from] -= 1;
        balanceOf[to] += 1;
        _owners[tokenId] = to;
        emit Transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public {
        transferFrom(from, to, tokenId);
        if (to.code.length > 0) {
            require(_checkOnERC721Received(from, to, tokenId, data), "ERC721: transfer to non ERC721Receiver");
        }
    }

    function _checkOnERC721Received(address from, address to, uint256 tokenId, bytes memory data) private returns (bool) {
        (bool ok, bytes memory ret) = to.call(
            abi.encodeWithSelector(0x150b7a02, msg.sender, from, tokenId, data)
        );
        if (!ok) return false;
        return ret.length == 4 && abi.decode(ret, (bytes4)) == bytes4(0x150b7a02);
    }

    function _toString(uint256 value) private pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    receive() external payable {}
}
