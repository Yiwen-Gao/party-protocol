# Crowdfund Contracts

These contracts allow people to create and join a crowdfund, pooling ETH together to acquire an NFT. Multiple crowdfund contracts exist for specific acquisition patterns.

---

## Key Concepts

- **Crowdfunds**: Contracts implementing various strategies that allow people to pool ETH together to acquire an NFT, with the end goal of forming a Party around it.
- **Crowdfund NFT**: A _soulbound_ NFT (ERC721) representing a contribution made to a Crowdfund. Each contributor gets one of these the first time they contribute. At the end of the crowdfund (successful or unsuccessful), a Crowdfund NFT can be burned, either to redeem unused ETH or to claim a governance NFT in the new Party.
- **Party**: The governance contract, which will be created and will custody the NFT after it has been acquired by the crowdfund.
- **Globals**: A single contract that holds configuration values, referenced by several ecosystem contracts.
- **Proxies**: All crowdfund instances are deployed as simple [`Proxy`](../contracts/utils/Proxy.sol) contracts that forward calls to a specific crowdfund implementation that inherits from `Crowdfund`.

---

## Contracts

The main contracts involved in this phase are:

- `CrowdfundFactory`([code](../contracts/crowdfund/CrowdfundFactory.sol))
  - Factory contract that deploys a new proxified `Crowdfund` instance.
- `Crowdfund` ([code](../contracts/crowdfund/Crowdfund.sol))
  - Abstract base class for all crowdfund contracts. Implements most contribution accounting and end-of-life logic for crowdfunds.
- `BuyCrowdfund` ([code](../contracts/crowdfund/BuyCrowdfund.sol))
  - A crowdfund that purchases a specific NFT (i.e., with a known token ID) below a maximum price.
- `CollectionBuyCrowdfund` ([code](../contracts/crowdfund/CollectionBuyCrowdfund.sol))
  - A crowdfund that purchases any NFT from a collection (i.e., any token ID) from a collection below a maximum price. Like `BuyCrowdfund` but allows any token ID in a collection to be bought.
- `CollectionBatchBuyCrowdfund` ([code](../contracts/crowdfund/CollectionBatchBuyCrowdfund.sol))
  - A crowdfund that purchases multiple NFTs with any token ID from a collection below a maximum price. Like `CollectionBuyCrowdfund`, but allows the acquisition of several eligible NFTs in a single batch transaction.
- `AuctionCrowdfund` ([code](../contracts/crowdfund/AuctionCrowdfund.sol))
  - A crowdfund that can repeatedly bid in an auction for a specific NFT (i.e., with a known token ID) until the auction ends.
- `IMarketWrapper` ([code](../contracts/crowdfund/IMarketWrapper.sol))
  - A generic interface consumed by `AuctionCrowdfund` to abstract away interactions with any auction marketplace.
- `IGateKeeper` ([code](../contracts/gatekeepers/IGateKeeper.sol))
  - An interface implemented by gatekeeper contracts that restrict who can participate in a crowdfund. There are currently two implementations of this interface:
    - `AllowListGateKeeper` ([code](../contracts/gatekeepers/AllowListGateKeeper.sol))
      - Restricts participation based on whether an address exists in a merkle tree.
    - `TokenGateKeeper` ([code](../contracts/gatekeepers/TokenGateKeeper.sol))
      - Restricts participation based on whether an address has a minimum balance of a token (ERC20 or ERC721).
- `Globals` ([code](../contracts/globals/Globals.sol))
  - A contract that defines global configuration values referenced by other contracts across the entire protocol.

![contracts](../.github/assets/crowdfund-contracts.png)

---

## Crowdfund Creation

The `CrowdfundFactory` contract is the canonical contract for creating crowdfund instances. It deploys `Proxy` instances that point to a specific implementation which inherits from `Crowdfund`.

### BuyCrowdfund Crowdfunds

`BuyCrowdfund`s are created via the `createBuyCrowdfund()` function. `BuyCrowdfund`s:

- Are trying to buy a specific ERC721 contract + token ID.
- While active, users can contribute ETH.
- Succeeds if anyone executes an arbitrary call with value through `buy()` which successfully acquires the NFT.
- Fails if the `expiry` time passes before acquiring the NFT.

#### Crowdfund Specific Creation Options

- `IERC721 nftContract`: The ERC721 contract of the NFT being bought.
- `uint256 nftTokenId`: ID of the NFT being bought.
- `uint40 duration`: How long this crowdfund has to bid on the NFT, in seconds.
- `uint96 maximumPrice`: Maximum amount of ETH this crowdfund will pay for the NFT. If zero, no maximum.
- `bool onlyHostCanBuy`: If this is `true`, only a host can call `buy()`.

### CollectionBuyCrowdfund Crowdfunds

`CollectionBuyCrowdfund`s are created via the `createCollectionBuyCrowdfund()` function. `CollectionBuyCrowdfund`s:

- Are trying to buy _any_ token ID on an ERC721 contract.
- While active, users can contribute ETH.
- Succeeds if the host executes an arbitrary call with value through `buy()` which successfully acquires an eligible NFT.
- Fails if the `expiry` time passes before acquiring an eligible NFT.

#### Crowdfund Specific Creation Options

- `IERC721 nftContract`: The ERC721 contract of the NFT being bought.
- `uint40 duration`: How long this crowdfund has to bid on an NFT, in seconds.
- `uint96 maximumPrice`: Maximum amount of ETH this crowdfund will pay for an NFT. If zero, no maximum.

### CollectionBatchBuyCrowdfund Crowdfunds

`CollectionBatchBuyCrowdfund`s are created via the `createCollectionBatchBuyCrowdfund()` function. `CollectionBatchBuyCrowdfund`s:

- Are trying to buy multiple NFTs of _any_ token ID on an ERC721 contract.
- While active, users can contribute ETH.
- Succeeds if the host executes an arbitrary call with values through `batchBuy()` which successfully acquires eligible NFTs.
- Fails if the `expiry` time passes before acquiring an eligible NFT.

#### Crowdfund Specific Creation Options

- `IERC721 nftContract`: The ERC721 contract of the NFT being bought.
- `bytes32 nftTokenIdsMerkleRoot`: The merkle root of the token IDs that can be bought. If null, any token ID in the collection can be bought.
- `uint96 maximumPrice`: Maximum amount of ETH this crowdfund will pay for an NFT. If zero, no maximum.

### AuctionCrowdfund Crowdfunds

`CollectionBuyCrowdfund`s are created via the `createAuctionCrowdfund()` function. `AuctionCrowdfund`s:

- Are trying to buy a specific ERC721 contract and specific token ID listed on an auction market.
- Directly interact with a Market Wrapper, which is an abstractions/wrapper of an NFT auction protocol.
  - These Market Wrappers are inherited from [v1 of the protocol](https://github.com/PartyDAO/PartyBid) and are actually delegatecalled into.
- While active, users can contribute ETH.
- While active, ETH bids can be placed by anyone via the `bid()` function.
- Succeeds when an allowed actor (e.g. host, contributor) calls `finalize()`, which attempts to settle the auction, and the crowdfund ends up holding the NFT.
- Fails if the `expiry` time passes before acquiring an eligible NFT.

#### Crowdfund Specific Creation Options

- `uint256 auctionId`: The auction ID specific to the `IMarketWrapper` instance being used.
- `IMarketWrapper market`: The auction protocol wrapper contract.
- `IERC721 nftContract`: The ERC721 contract of the NFT being bought.
- `uint256 nftTokenId`: ID of the NFT being bought.
- `uint40 duration`: How long this crowdfund has to bid on the NFT, in seconds.
- `uint96 maximumBid`: Maximum amount of ETH this crowdfund will bid on the NFT.
- `bool onlyHostCanBid`: If this is `true`, only a host can call `bid()`.

### Common Creation Options

In addition to the creation options described for each crowdfund type, there are a number of options common to all of them:

- `string name`: The name of the crowdfund/governance party.
- `string symbol`: The token symbol for crowdfund/governance party NFT.
- `uint256 customizationPresetId`: Customization preset ID to use for the crowdfund and governance NFTs. Defines how the crowdfund's `tokenURI()` SVG image will be rendered (e.g. color, light/dark mode).
- `address splitRecipient`: An address that receives a portion of voting power (or extra voting power) when the party transitions into governance.
- `uint16 splitBps`: What percentage (in basis points) of the final total voting power `splitRecipient` receives.
- `address initialContributor`: If ETH is attached during deployment, it will be interpreted as a contribution. This is who gets credit for that contribution.
- `address initialDelegate`: If there is an initial contribution, this is who they will initially delegate their voting power to when the crowdfund transitions to governance.
- `IGateKeeper gateKeeper`: The gatekeeper contract to use (if non-null) to restrict who can contribute to (and sometimes buy/bid in) this crowdfund.
- `bytes12 gateKeeperId`: The gate ID within the `gateKeeper` contract to use.
- `FixedGovernanceOpts governanceOpts`: Fixed [governance options](https://github.com/PartyDAO/party-protocol/blob/main/docs/governance.md#governance-options) that the governance Party will be created with if the crowdfund succeeds. Aside from the party `hosts`, only the hash of this field is stored on-chain at creation. It must be provided in full again in order for the party to win.

Crowdfunds are initialized with mostly fixed options, i.e. cannot be changed after creating a crowdfund. The only exception is `customizationPresetId`, which [can be changed later in the governance stage](https://github.com/PartyDAO/party-protocol/blob/main/docs/governance.md#governance-card-customization).

### Optional Gatekeeper Creation Data

Each of the mentioned creation functions can also take an optional `bytes createGateCallData` parameter which, if non-empty, will be called against the `gateKeeper` address in each crowdfund's creation options. The intent of this is to call a `createGate()` type function on a gatekeeper instance, so users can deploy a new crowdfund with a new gate in the same transaction. This function call is expected to return a `bytes12`, which will be decoded and will overwrite the `gateKeeperId` in the crowdfund's creation options. Neither the `createGateCallData` nor `gateKeeper` are scrutinized since the factory has no other responsibilities, privileges, or assets.

### Optional Initial Contribution

All creation functions are `payable`. Any ETH attached to the call will be attached to the deployment of the crowdfund's `Proxy`. This will be detected in the `Crowdfund` constructor and treated as an initial contribution to the crowdfund. The party's `initialContributor` option will designate who to credit for this contribution.

## Crowdfund Lifecycle

All crowdfunds share a concept of a lifecycle, wherein only certain actions can be performed. These are defined in `Crowdfund.CrowdfundLifecycle`:

- `Invalid`: The crowdfund does not exist.
- `Active`: The crowdfund has been created and contributions can be made and acquisition functions may be called.
- `Expired`: The crowdfund has passed its expiration time. No more contributions are allowed.
- `Busy`: A temporary state set by the contract during complex operations to act as a reentrancy guard.
- `Lost`: The crowdfund has failed to acquire the NFT in time. Contributors can reclaim their full contributions.
- `Won`: The crowdfund has acquired the NFT and it is now held by a governance party. Contributors can claim their governance NFTs or reclaim unused ETH.

## Crowdfund Card Customization

The creator of a crowdfund can customize how they want their crowdfund's NFT card to look. Currently, this means picking a color and choosing a light or dark theme. This setting will also be carry over to the governance NFTs should the crowdfund win.

Customization is done by choosing the `customizationPresetId` parameter that crowdfunds are initialized with, beginning at ID 1. Note that ID 0 is reserved and has [special meaning within the protocol](https://github.com/PartyDAO/party-protocol/blob/main/docs/governance.md#governance-card-customization). Although it should never be used by crowdfunds, if set the crowdfund card will fallback to the default design. The same will happen if an invalid `customizationPresetID` (e.g. an ID that doesn't exist) is chosen.

## Making Contributions

While the crowdfund is in the `Active` lifecycle, users can contribute ETH to it.

The only way of contributing to a crowdfund is through the payable `contribute()` function. Contribution records are created per-user, tracking the individual contribution amount as well as the overall total contribution amount, in order to determine what fraction of each user's contribution was used by a successful crowdfund.

### Crowdfund NFTs

The first time a user contributes, they are minted a _soulbound_ Crowdfund NFT, which is implemented by the crowdfund contract itself. This NFT can later be burned to refund unused ETH and/or mint an NFT containing voting power in the governance Party.

A contributor can only own one crowdfund NFT; multiple contributions by the same contributor will not mint them additional crowdfund NFTs.

### Accounting

Every contribution made is recorded and stored in an array under the contributor's address.

For each contribution, two details are stored: 1) the `amount` contributed and 2) the `previousTotalContributions` when the contribution was made.

To determine whether a contribution was unused after a crowdfund has concluded, the contract compares the `previousTotalContributions` against the `totalEthUsed` to acquire the NFT.

- If `previousTotalContributions + amount <= totalEthUsed`, then the entire contribution was used.
- If `previousTotalContributions >= totalEthUsed`, then the entire contribution was unused and refunded to the contributor.
- Otherwise, only `totalEthUsed - previousTotalContributions` of the contribution was used and the rest should be refunded to the contributor.

Unused contributions can be reclaimed after the party has either lost or won. For example, if a crowdfund raised 10 ETH to acquire an NFT that was won at 7 ETH, the 3 ETH leftover will be refunded. If the party lost, all 10 ETH will be refunded.

The accounting logic for all this is handled in the `Crowdfund` contract from which all crowdfund types inherit from.

### Extra Parameters

The `contribute()` function accepts a delegate parameter, which will be the user's initial delegate when they mint their voting power in the governance party. Future contributions (even 0-value contributions) can change the initial delegate. It is valid to call `contribute()` with `0` value even after the crowdfund expires or ends in order to update a user's chosen delegate.

The `contribute()` function accepts a `gateData` parameter, which will be passed to the gatekeeper a party has chosen (if any). If there is a gatekeeper in use, this arbitrary data must be used by the gatekeeper to prove that the contributor is allowed to participate.

## Winning

Each crowdfund type has its own criteria and operations for winning.

### BuyCrowdfund

`BuyCrowdfund` wins if an allowed actor successfully calls `buy()` before the crowdfund expires.

Who can call `buy()` is determined by `onlyHostCanBuy` and if the crowdfund uses a gatekeeper. If `onlyHostCanBuy`, then only a host can call it. If the crowdfund uses a gatekeeper, then only contributors may call it. The former case takes precedent over the latter, meaning if both are true then only the host can call it.

The `buy()` function will perform an arbitrary call with value of ETH (up to `maximumPrice`) to attempt to acquire the predetermined NFT. The NFT must be held by the party after the arbitrary call successfully returns. It will then proceed with creating a governance Party.

### CollectionBuyCrowdfund

`CollectionBuyCrowdfund` wins if a _host_ successfully calls `buy()` before the crowdfund expires. The `buy()` function will perform an arbitrary call with value (up to `maximumPrice`) to attempt to acquire _any_ NFT token ID from the predetermined ERC721. The NFT must be held by the party after the arbitrary call successfully returns. It will then proceed with creating a governance Party, unless the NFT was acquired for free (or "gifted"). In this case, it will refund all contributors for their original contribution amounts and declare a loss.

### CollectionBatchBuyCrowdfund

`CollectionBatchBuyCrowdfund` wins if a _host_ successfully calls `batchBuy()` before the crowdfund expires. The `batchBuy()` function will perform multiple arbitrary calls with value (up to `maximumPrice` for each NFT) to attempt to acquire multiple NFTs with any token ID from the predetermined ERC721 collection. The NFTs must be held by the crowdfund, and the total value of ETH used in the purchase must meet the specified minimum requirements. Additionally, the number of NFTs bought must not be less than the `minTokensBought` parameter. It will then proceed with creating a governance Party, unless all the NFTs were acquired for free (or "gifted"). In this case, it will refund all contributors for their original contribution amounts and declare a loss.

### AuctionCrowdfund

`AuctionCrowdfund` requires more steps and active intervention than the other crowdfunds because it needs to interact with auctions.

While the crowdfund is Active, only allowed parties can call `bid()` to bid on the auction the crowdfund was started around.

Who can call `bid()` is determined by `onlyHostCanBid` and if the crowdfund uses a gatekeeper. If `onlyHostCanBid`, then only a host can call it. If the crowdfund uses a gatekeeper, then only contributors may call it. The former case takes precedent over the latter, meaning if both are true then only the host can call it.

For each `bid()` call, the amount to bid will be the minimum winning amount determined by the Market Wrapper being used. Only up to `maximumBid` ETH will ever be used in a bid. The crowdfund contract will `delegatecall` into the Market Wrapper to perform the bid, so it is important that a crowdfund only uses trusted Market Wrappers.

After the auction has ended, someone must call `finalize()`, regardless of whether the crowdfund has placed a bid or not. This will settle the auction (if necessary), possibly returning bidded ETH to the party or acquiring the auctioned NFT. It is possible to call `finalize()` even after the crowdfund has Expired and the crowdfund may even still win in this scenario. If the NFT was acquired, it will then proceed with creating a governance party.

If the `onlyHostCanBid` option is set, then only a host will be able to call `bid()`.

### Creating a Governance Party

In every crowdfund, immediately after the party has won by acquiring the NFT, it will create a new governance Party instance, using the same fixed governance options provided at crowdfund creation. The `totalVotingPower` the governance Party is created with is simply the settled price of the NFT (how much ETH we paid for it). The bought NFT is immediately transferred to the governance Party as well.

After this point, the crowdfund will be in the `Won` lifecycle and no more contributions will be allowed. Contributors can `burn()` their Crowdfund NFT to refund any ETH they contributed that was not used, as well as mint a governance NFT containing voting power within the Party.

## Losing

Crowdfunds generally lose when they expire before acquiring a target NFT. The one exception is `AuctionCrowdfund`, which can still be finalized and win after expiration if it holds the NFT.

When a crowdfund enters the Lost lifecycle, contributors may `burn()` their Crowdfund NFT to refund all the ETH they contributed.

## Burning

At the conclusion of a crowdfund (Won or Lost lifecycle), contributors may burn their Crowdfund NFT via the `burn()` function.

If the crowdfund lost, burning the participation NFT will refund all of the contributor's contributed ETH.

If the crowdfund won, burning the participation NFT will refund any of the contributor's _unused_ ETH and mint voting power in the governance party.

### Calculating Voting Power

Voting power for a contributor is equivalent to the amount of ETH they contributed that was used to acquire the NFT. Each individual contribution is tracked against the total ETH raised at the time of contribution. If a user contributes after the crowdfund received enough ETH to acquire the NFT, only their contributions from prior will count towards their final voting power. All else will be refunded when they burn their Crowdfund NFT.

If the crowdfund was created with a valid `splitBps` value, this percent of every contributor's voting power will be reserved for the `splitRecipient` to claim. If they are also a contributor, they will receive the sum of both.

### Burning Someone Else's NFT

It's not uncommon for contributors to go inactive before a crowdfund ends. To help ensure that members in the governance party have enough voting power to operate in the proposal flow as quickly as possible, anyone can burn any contributor's Crowdfund NFT. Doing so will credit the contributor's delegate in the governance Party with the contributor's voting power, enabling the delegate to begin using that voting power.

## Gatekeepers

Gatekeepers allow crowdfunds to limit who can contribute to them. Each gatekeeper implementation stores multiple "gates," i.e. a set of conditions used to define whether a participant `isAllowed` to contribute to a crowdfund. Each gate has its own ID.

For certain crowdfunds, e.g. `AuctionCrowdfund` and `BuyCrowdfund`, using a gatekeeper also limits who can perform certain actions. For example, for a `BuyCrowdfund` it limits who can call `buy()` to only contributors (as opposed to anybody being able to call it if `onlyHostCanBuy` is false).

When a crowdfund is created, users can choose to create a new gate within a gatekeeper implementation or use an existing one by passing in its gate ID. There are currently two gatekeeper types supported:

- [TokenGateKeeper](https://github.com/PartyDAO/party-protocol/blob/main/docs/crowdfund.md#tokengatekeeper)
- [AllowListGateKeeper](https://github.com/PartyDAO/party-protocol/blob/main/docs/crowdfund.md#allowlistgatekeeper)

### TokenGateKeeper

This gatekeeper only allows contributions from holders of a specific token (e.g. ERC20 or ERC721) above a specific balance. Each gate stores the token and minimum balance it requires for participation when the gate is created. While ERC20 and ERC721 tokens will be the predominant usecase, any contract that implements `balanceOf()` can be used to gate.

### AllowListGateKeeper

This gatekeeper only allows contributions from addresses on an allowlist. The gatekeeper stores a [merkle root](https://www.investopedia.com/terms/m/merkle-root-cryptocurrency.asp) it uses to check whether an address belongs in the allowlist or not using a [proof](https://github.com/dragonfly-xyz/useful-solidity-patterns/tree/main/patterns/merkle-proofs) provided along with their address. Each gate stores the merkle root it uses which is set when the gate is created.
