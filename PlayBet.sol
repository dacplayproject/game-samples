pragma solidity ^0.4.11;

import "./Owned.sol";
import "./SafeMath.sol";

contract PlayBet is Owned {
    using SafeMath for uint256;

    struct Bet {
        // player
        address player;
        bytes32 secretHash;
        uint256 amount;
        uint roundId;

        // flag
        bool isRevealed;

        // reveal time
        uint num;
        bool guessOdd;
        bytes32 secret;
    }

    struct Round {
        uint betCount;
        uint maxBetBlockCount;      // Max Block Count for wating others to join betting, will return funds if no enough bets join in.
        uint maxRevealBlockCount;   // Should have enough minimal blocks e.g. >100

        uint[] betIds;

        uint startBetBlock;
        uint startRevealBlock;

        uint finalizedBlock;
    }

    uint public betCount;
    uint public roundCount;

    mapping(uint => Bet) public bets;
    mapping(uint => Round) public rounds;
    mapping(address => uint) public balancesForWithdraw;

    uint poolAmount;

    uint256 public initializeTime;

    function PlayBet()
    {
        initializeTime = now;

        roundCount = 1;
    }
    
    function startRoundWithFirstBet(uint _betCount, uint _maxBetBlockCount, uint _maxRevealBlockCount, bytes32 _secretHashForFirstBet) payable public returns (uint roundId)
    {
        require(_betCount >= 2);
        require(_maxBetBlockCount >= 100);
        require(_maxRevealBlockCount >= 100);

        require(msg.value>0);

        uint betId = addBet(msg.sender, _secretHashForFirstBet, msg.value);

        roundId = addRound(_betCount, _maxBetBlockCount, _maxRevealBlockCount, betId);
    }

    function betWithRound(uint _roundId, bytes32 _secretHashForBet) payable public
    {
        require(msg.value>0);
        require(rounds[_roundId].finalizedBlock != 0);
        
        require(rounds[_roundId].betIds.length < rounds[_roundId].betCount);


        for (uint i=0; i<rounds[_roundId].length; i++) {
            if (bets[rounds[_roundId].betIds[i]].player == msg.sender)
                throw;
        }

        uint betId = addBet(msg.sender, _secretHashForBet, msg.value);

        rounds[_roundId].betIds.push(betId);

        bets[betId]._roundId = _roundId;

        if (rounds[_roundId].betIds.length == rounds[_roundId].betCount)
        {
            rounds[_roundId].startRevealBlock = getBlockNumber();
        }
    }

    function revealBet(uint betId, uint _num, bool _guessOdd, bytes32 _secret) public returns (bool)
    {
        Bet bet = bets[betId];
        Round round = rounds[bet.roundId];
        require(round.betIds.length == round.betCount);
        require(!round.finalize);

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

    /*
     * Internal functions
     */
    /// @dev Adds a new bet to the bet mapping, if bet does not exist yet.
    /// @param destination Transaction target address.
    /// @param value Transaction ether value.
    /// @param data Transaction data payload.
    /// @return Returns bet ID.
    function addBet(address _player, bytes32 _secretHash, uint256 _amount)
        internal
        notNull(player)
        returns (uint betId)
    {
        betId = betCount;
        bets[betId] = Bet({
            player: player,
            secretHash: _secretHash,
            amount: _amount,
            roundId: 0,
            isRevealed: false,
            num:0,
            guessOdd:false,
            secret: ""
        });
        betCount += 1;
        BetSubmission(betId);
    }

    function addRound(uint _betCount, uint _maxBetBlockCount, uint _maxRevealBlockCount, uint _betId)
        internal
        returns (uint roundId)
    {
        roundId = roundCount;
        rounds[roundId] = Round({
            betCount: _betCount,
            maxBetBlockCount: _maxBetBlockCount,
            maxRevealBlockCount: _maxRevealBlockCount,
            betIds: [_betId],
            finalizedBlock: 0
        });

        bets[_betId].roundId = roundId;

        roundCount += 1;
        RoundSubmission(roundId);
    }

    // anyone can try to finalize after the max block count or bets in the round are all revealed.
    function finalizeRound(uint roundId) public
    {
        Round round = rounds[roundId];

        require(round.finalizedBlock != 0);

        uint finalizedBlock = getBlockNumber();
        if (round.betIds.length < round.betCount && finalizedBlock.sub(round.startBetBlock) > round.maxBetBlockCount)
        {
            // betting timeout
            // return funds to players

            for (uint i=0; i<round.betIds.length; i++) {
                Bet bet = bets[round.betIds[i]];
                balancesForWithdraw[bet.player] = balancesForWithdraw[bet.player].add(bet.amount);
            }

            round.finalizedBlock = finalizedBlock;
            return;
        } else if (round.betIds.length == round.betCount) {
            bool betsRevealed = true;

            for (uint i=0; i<round.betIds.length; i++) {
                Bet bet = bets[round.betIds[i]];
                if (!bet.isRevealed)
                {
                    betsRevealed = false;
                    break;
                }
            }

            if (betsRevealed)
            {
                uint jackpotSum;
                uint jackpotNum;
        
                uint oddCount;
                uint oddSum;
                uint evenCount;
                uint evenSum;

                for (uint i=0; i<round.betIds.length; i++) {
                    Bet bet = bets[round.betIds[i]];
                    jackpotSum = jackpotSum.add(bet.amount);
                    jackpotNum = jackpotNum.add(uint(bet.secret));
                    
                    if(bet.guessOdd){
                        oddCount++;
                        oddSum = oddSum.add(bet.amount);
                    }else{
                        evenCount++;
                        evenSum = evenSum.add(bet.amount);
                    }
                }

                bool isOddWin = (jackpotNum % 2 == 1) ? true : false;

                uint winnerNumber = isOddWin ? oddCount: evenCount;

                if (oddCount == 0 || evenCount == 0)
                {
                    winnerNumber = oddCount > 0 ? oddCount : evenCount;
                    isOddWin = oddCount > 0 ? true : false;
                }

                uint dustLeft = jackpotSum;
                for (uint i=0; i<round.betIds.length; i++) {
                    Bet bet = bets[round.betIds[i]];

                    if (isOddWin && bet.guessOdd)
                    {
                        uint reward = bet.amount.mul(jackpotSum).div(oddSum);
                        balancesForWithdraw[bet.player] = balancesForWithdraw[bet.player].add(reward);
                        dustLeft = dustLeft.sub(reward);
                    } else if (!isOddWin && !bet.guessOdd)
                    {
                        uint reward = bet.amount.mul(jackpotSum).div(evenSum);
                        balancesForWithdraw[bet.player] = balancesForWithdraw[bet.player].add(reward);
                        dustLeft = dustLeft.sub(reward);
                    }
                }

                poolAmount = poolAmount.add(dustLeft);

                round.finalizedBlock = finalizedBlock;
                return;
            }
            else if (!betsRevealed && finalizedBlock.sub(round.startRevealBlock) > round.maxBetBlockCount)
            {
                // return funds to players who have already revealed
                // but for those who didn't reveal, the funds go to pool
                // revealing timeout

                for (uint i=0; i<round.betIds.length; i++) {
                    Bet bet = bet[round.betIds[i]];
                    if (bet.isRevealed)
                    {
                        balancesForWithdraw[bet.player] = balancesForWithdraw[bet.player].add(bet.amount);
                    } else
                    {
                        // go to pool
                        poolAmount = poolAmount.add(bet.amount);
                    }
                }

                round.finalizedBlock = finalizedBlock;
                return;
            } else{
                throw;
            }
        } else
        {
            throw;
        }
    }

    /// @notice This function is overridden by the test Mocks.
    function getBlockNumber() internal constant returns (uint256) {
        return block.number;
    }

    function withdraw() public returns (bool)
    {
        var amount = balancesForWithdraw[msg.sender];
        if (amount > 0) {
            balancesForWithdraw[msg.sender] = 0;

            if (!msg.sender.send(amount)){
                // No need to call throw here, just reset the amount owing
                balancesForWithdraw[msg.sender] = amount;
                return false;
            }
        }
        return true;
    }

    function claimFromPool() public onlyOwner
    {
        owner.transfer(poolAmount);
        ClaimFromPool();
    }

    event BetSubmission(uint indexed _betId);
    event BetSubmission(uint indexed _roundId);

    event ClaimFromPool();
    
    event TestSha2(bytes32);
}
