pragma solidity ^0.4.11;

contract PlayBet {
    struct Bet {
        // player
        address player;
        
        // bet time
        bytes32 secretBet;
        uint deposit;

        // flag
        bool isRevealed;

        // reveal time
        uint num;
        bool guessOdd;
        bytes32 secret;
    }

    address[] public allPlayers;
    uint public playerNumber;

    mapping(address => Bet) public playerToBets;
    mapping(address => uint) public pendingReturns;

    
    event TestSha2(bytes32);

    uint public initTime;

    function PlayBet()
    {
        initTime = now;
    }
    

    function bet(bytes32 _secretBet) payable 
    {
        require(msg.value>0);
        require( playerNumber <2 );
        require( playerToBets[msg.sender].player == address(0x0));

        allPlayers.push(msg.sender);
        playerNumber++;
        playerToBets[msg.sender] = Bet({
                player: msg.sender,
                secretBet: _secretBet,
                deposit: msg.value,
                isRevealed: false,
                num:0,
                guessOdd:false,
                secret: ""
            });
    }

    function revealBet(uint _num, bool _guessOdd, bytes32 _secret)
        returns(bool)
    {
        Bet bet = playerToBets[msg.sender];

        if (bet.secretBet == keccak256(_num, _guessOdd, _secret) )
        {
            bet.isRevealed = true;
            bet.num = _num;
            bet.guessOdd = _guessOdd;
            bet.secret = _secret;
            
            return true;
        }
        
        return false;
    }

    // TODO: who/when to end the bets
    function endBet()
    {
        require(playerNumber>0);

        uint numSum;
        uint depositSum;
        
        address[] memory guessOddPlayers = new address[](playerNumber);
        address[] memory guessEvenPlayers = new address[](playerNumber);
        uint oddIndex; uint evenIndex;

        for(uint i = 0; i < playerNumber ; i++){
            Bet bet = playerToBets[allPlayers[i]];

            depositSum += bet.deposit;
            
            if (! bet.isRevealed )
                continue;
            numSum += bet.num;
            
            if(bet.guessOdd){
                guessOddPlayers[oddIndex] = bet.player;
                oddIndex++;
            }else{
                guessEvenPlayers[evenIndex] = bet.player;
                evenIndex++;
            }
        }
        
        uint winnerNumber = (numSum%2 == 1)? oddIndex: evenIndex;
        address[] memory winners;
        
        if(winnerNumber == 0) { // all player lose bet
            winners = allPlayers; 
            winnerNumber = playerNumber;
        }else{
            winners = (numSum%2 == 1)? guessOddPlayers: guessEvenPlayers;
        }
        
        uint reward = depositSum/winnerNumber;
        
        for(i =0; i < winnerNumber; i ++){
            pendingReturns[winners[i]] +=  reward;
        }

        //clean up    
        playerNumber = 0;
    }


    function withdraw() 
        returns (bool) 
    {
        var amount = pendingReturns[msg.sender];
        if (amount > 0) {
            pendingReturns[msg.sender] = 0;

            if (!msg.sender.send(amount)){
                // No need to call throw here, just reset the amount owing
                pendingReturns[msg.sender] = amount;
                return false;
            }
        }
        return true;
    }
}
