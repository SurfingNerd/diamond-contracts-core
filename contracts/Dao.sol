pragma solidity =0.8.17;

struct UpgradeBallot {

    uint256 ballotID;

    address permission;
    address random;
    address reward;
    address staking;
    address validatorSet;
    
    /// this is the part that should be solved in OpenZeppelin ? 
    uint256 votesYes;
    uint256 votesNo;

    /// End date in unix timestamp
    uint256 end;
    
    bool executed;
    mapping(address => bool) voted;
}

struct TransferBallot {
    /** todo */
    uint256 id;
}

/// Diamond DAO central point of operation.
/// - Manages the DAO funds.
/// - Is able to upgrade all diamond-contracts-core contracts, including itself.
/// - Is able to vote for chain settings.
contract DiamondDao {

    mapping (uint256 => UpgradeBallot) upgradeBallots;
    mapping (uint256 => TransferBallot) transferBallots;
        
    function registerServices(/** todo: Service address list */ ) external {

        // throw if Services  have already be registered.

    }

    function executeUpgrades(uint256 upgrade_ballot_id) external {
        /** todo: does all checks and executes the upgrades */
        /** idea: maybe we could auto trigger upgrades, for example on epoch switches */
    }

    function createTransferBallot(/** all params for a transfer call  */ ) external {
        /** todo */
    }

    function createUpgradeBallot(/*** todo: List of contract adresses. 0x0 means no upgrade for this contract */  ) external {

    }

    function executeTransferFunds(uint ballot) external {

        /** todo */
    }


    function executeUpgrade(uint ballot) external {
        /** todo */
    }

    /// this list would go on forever,
    /// bUt all usual ballots like TransferErc20, TransferERC721 
    /// are already solved in implementations of (gnosis) global safe.
    /// here we could use multisend. 
}