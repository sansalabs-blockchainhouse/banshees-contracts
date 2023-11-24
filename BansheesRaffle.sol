// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract BansheesRaffle is ReentrancyGuard, ERC1155Holder, AccessControl {
    IERC20 public erc20Token;
    address payable public funds;
    address public StakingContract;
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    enum RaffleState {
        Open,
        Calculating,
        Closed
    }

    enum RaffleType {
        Normal,
        Token,
        NormalWithFree,
        TokenWithFree,
        NormalOrToken,
        NormalOrTokenOrFree
    }

    enum NFTType {
        ERC721,
        ERC155
    }

    struct Raffle {
        address creator;
        address nftContract;
        uint256 nftId;
        string name;
        string image;
        uint256[] ticketPrice;
        uint256 ticketsBought;
        RaffleState raffleState;
        RaffleType raffleType;
        NFTType nftType;
        address[] tickets;
        uint256 startDate;
        uint256 endDate;
        address winner;
    }

    Raffle[] public raffles;

    mapping(address => uint256) public freeTickets;

    event TicketPurchased(
        uint256 indexed ticketId,
        uint256 indexed raffleId,
        address indexed buyer,
        uint256 ticketCount
    );

    constructor(address _erc20Token, address payable _funds) {
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        erc20Token = IERC20(_erc20Token);
        funds = _funds;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155Receiver, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function createRaffle(
        address _nftContract,
        uint256 _nftId,
        uint256[] memory _ticketPrice,
        string memory _name,
        string memory _image,
        uint256 _startDate,
        uint256 _endDate,
        RaffleType _raffleType,
        NFTType _nftType
    ) external nonReentrant {
        require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not admin");
        require(_nftContract != address(0), "Invalid NFT contract address");
        if (_nftType == NFTType.ERC721) {
            IERC721 nftContract = IERC721(_nftContract);
            require(
                nftContract.ownerOf(_nftId) == msg.sender,
                "You are not the owner of NFT"
            );

            nftContract.transferFrom(msg.sender, address(this), _nftId);
        }
        if (_nftType == NFTType.ERC155) {
            IERC1155 nftContract = IERC1155(_nftContract);
            require(
                nftContract.balanceOf(msg.sender, _nftId) >= 1,
                "You are not the owner of NFT"
            );

            nftContract.safeTransferFrom(
                msg.sender,
                address(this),
                _nftId,
                1,
                ""
            );
        }

        raffles.push(
            Raffle(
                msg.sender,
                _nftContract,
                _nftId,
                string(abi.encodePacked(_name)),
                string(abi.encodePacked(_image)),
                _ticketPrice,
                0,
                RaffleState.Open,
                _raffleType,
                _nftType,
                new address[](0),
                _startDate,
                _endDate,
                address(0)
            )
        );
    }

    function enterRaffle(uint256 _raffleId, uint256 _ticketCount)
        external
        payable
        nonReentrant
    {
        require(_raffleId < raffles.length, "Invalid raffle ID");
        require(_ticketCount > 0, "Invalid ticket count");

        Raffle storage raffle = raffles[_raffleId];

        uint256 totalPrice = raffle.ticketPrice[0] * _ticketCount;
        require(msg.value >= totalPrice, "Insufficient payment");

        require(raffle.raffleState == RaffleState.Open, "Raffle not open");
        require(block.timestamp >= raffle.startDate, "Raffle not started yet");
        require(block.timestamp <= raffle.endDate, "Raffle has ended");

        for (uint256 i = 0; i < _ticketCount; i++) {
            raffle.tickets.push(msg.sender);
            raffle.ticketsBought++;
        }

        emit TicketPurchased(
            raffle.tickets.length - 1,
            _raffleId,
            msg.sender,
            _ticketCount
        );
    }

    function enterRaffleFreeTickets(uint256 _raffleId, uint256 _ticketCount)
        external
        nonReentrant
    {
        require(_raffleId < raffles.length, "Invalid raffle ID");
        require(_ticketCount > 0, "Invalid ticket count");
        require(freeTickets[msg.sender] >= _ticketCount, "Not enough tickets");

        Raffle storage raffle = raffles[_raffleId];

        require(
            raffle.raffleType == RaffleType.NormalWithFree ||
                raffle.raffleType == RaffleType.TokenWithFree ||
                raffle.raffleType == RaffleType.NormalOrTokenOrFree,
            "Invalid Raffle Type"
        );

        require(raffle.raffleState == RaffleState.Open, "Raffle not open");
        require(block.timestamp >= raffle.startDate, "Raffle not started yet");
        require(block.timestamp <= raffle.endDate, "Raffle has ended");

        for (uint256 i = 0; i < _ticketCount; i++) {
            raffle.tickets.push(msg.sender);
            raffle.ticketsBought++;
        }

        freeTickets[msg.sender] -= _ticketCount;

        emit TicketPurchased(
            raffle.tickets.length - 1,
            _raffleId,
            msg.sender,
            _ticketCount
        );
    }

    function enterRaffleErc20(uint256 _raffleId, uint256 _ticketCount)
        external
        nonReentrant
    {
        require(_raffleId < raffles.length, "Invalid raffle ID");
        require(_ticketCount > 0, "Invalid ticket count");

        Raffle storage raffle = raffles[_raffleId];

        uint256 totalPrice = raffle.ticketPrice[1] * _ticketCount;
        require(
            erc20Token.balanceOf(msg.sender) >= totalPrice,
            "Insufficient token balance"
        );

        erc20Token.transferFrom(msg.sender, funds, totalPrice);

        require(raffle.raffleState == RaffleState.Open, "Raffle not open");
        require(block.timestamp >= raffle.startDate, "Raffle not started yet");
        require(block.timestamp <= raffle.endDate, "Raffle has ended");

        for (uint256 i = 0; i < _ticketCount; i++) {
            raffle.tickets.push(msg.sender);
            raffle.ticketsBought++;
        }

        emit TicketPurchased(
            raffle.tickets.length - 1,
            _raffleId,
            msg.sender,
            _ticketCount
        );
    }

    function getAllRaffles() public view returns (Raffle[] memory) {
        return raffles;
    }

    function returnNFTAndDeleteRaffle(uint256 _raffleId) external nonReentrant {
        require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not admin");

        require(_raffleId < raffles.length, "Invalid raffle ID");

        Raffle storage raffle = raffles[_raffleId];

        require(raffle.winner == address(0), "Raffle already has a winner");
        if (raffle.nftType == NFTType.ERC721) {
            IERC721 nftContract = IERC721(raffle.nftContract);

            nftContract.transferFrom(address(this), msg.sender, raffle.nftId);
        }
        if (raffle.nftType == NFTType.ERC155) {
            IERC1155 nftContract = IERC1155(raffle.nftContract);
            nftContract.safeTransferFrom(
                address(this),
                msg.sender,
                raffle.nftId,
                1,
                ""
            );
        }
        if (_raffleId < raffles.length - 1) {
            raffles[_raffleId] = raffles[raffles.length - 1];
        }
        raffles.pop();
    }

    function withdrawalAll() external nonReentrant {
        require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not admin");
        uint256 balance = address(this).balance;
        require(balance > 1 ether, "your balance ould be 1 ether or more");
        (bool success, ) = msg.sender.call{value: balance}("");
        require(success, "transaction failed");
    }

    function setFreeTickets(address wallet, uint256 value) external {
        require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not admin");
        freeTickets[wallet] += value;
    }

    function getFreeTickets(address wallet) external view returns (uint256) {
        return freeTickets[wallet];
    }

    function setRaffleStatusCalculating(uint256 index) external {
        require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not admin");
        raffles[index].raffleState = RaffleState.Calculating;
    }

    function sendRafflePrize(address _winner, uint256 index) external {
        require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not admin");
        raffles[index].winner = _winner;
        raffles[index].raffleState = RaffleState.Closed;

        if (raffles[index].nftType == BansheesRaffle.NFTType.ERC721) {
            IERC721 nftContract = IERC721(raffles[index].nftContract);
            nftContract.safeTransferFrom(
                address(this),
                _winner,
                raffles[index].nftId
            );
        }
        if (raffles[index].nftType == BansheesRaffle.NFTType.ERC155) {
            IERC1155 nftContract = IERC1155(raffles[index].nftContract);
            nftContract.safeTransferFrom(
                address(this),
                _winner,
                raffles[index].nftId,
                1,
                ""
            );
        }
    }

    function getRafflesInfo(uint256 index)
        public
        view
        returns (
            uint256,
            uint256,
            RaffleState
        )
    {
        return (
            raffles.length,
            raffles[index].endDate,
            raffles[index].raffleState
        );
    }

    function getRafflesInfoTickets(uint256 index)
        public
        view
        returns (RaffleState, address[] memory)
    {
        return (raffles[index].raffleState, raffles[index].tickets);
    }
}
