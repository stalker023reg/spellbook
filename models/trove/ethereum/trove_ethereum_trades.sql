{{ config(
    schema = 'trove_ethereum',
    alias = 'trades',
    post_hook = '{{ expose_spells(\'["ethereum"]\',
                                    "project",
                                    "trove",
                                    \'["bizzyvinci"]\') }}'
)}}


with marketplace as (
    select
        evt_block_time as block_time,
        tokenId as token_id,
        case
            when quantity='1' then 'Single Item Trade'
            else 'Bulk Purchase'
        end as trade_type,
        cast(quantity as decimal(38, 0)) as number_of_items,
        'Buy' as trade_category,
        seller,
        buyer,
        cast(pricePerItem as decimal(38, 0)) * cast(quantity as decimal(38, 0)) as amount_raw,
        paymentToken as currency_contract,
        nftAddress as nft_contract_address,
        contract_address as project_contract_address,
        evt_tx_hash as tx_hash,
        evt_block_number as block_number
    from (
        select evt_block_time, tokenId, quantity, seller, pricePerItem,
            paymentToken, nftAddress, evt_tx_hash, evt_block_number,
            contract_address, bidder as buyer
        from {{ source('treasure_trove_ethereum', 'TreasureMarketplace_evt_BidAccepted') }}
        union all
        select evt_block_time, tokenId, quantity, seller, pricePerItem,
            paymentToken, nftAddress, evt_tx_hash, evt_block_number,
            contract_address, buyer
        from {{ source('treasure_trove_ethereum', 'TreasureMarketplace_evt_ItemSold') }}
    )
)


select
    'ethereum' as blockchain,
    'trove' as project,
    cast(null as varchar(5)) as version,
    mp.block_time,
    token_id,
    nft_tokens.name as collection,
    cast(prices.price * amount_raw / power(10, erc20.decimals) as double) as amount_usd,
    nft_tokens.standard as token_standard,
    trade_type,
    number_of_items,
    trade_category,
    'Trade' as evt_type,
    seller,
    buyer,
    cast(amount_raw / power(10, erc20.decimals) as double) as amount_original,
    amount_raw,
    erc20.symbol as currency_symbol,
    currency_contract,
    nft_contract_address,
    project_contract_address,
    cast(null as varchar(5)) as aggregator_name,
    cast(null as varchar(5)) as aggregator_address,
    mp.tx_hash,
    mp.block_number,
    tx.`from`  as tx_from,
    tx.to as tx_to,
    cast(null as varchar(5)) as unique_trade_id
from marketplace mp
inner join {{ source('ethereum', 'transactions') }} tx
    on tx.hash = mp.tx_hash
left join {{ ref('tokens_ethereum_erc20') }} erc20
    on erc20.contract_address = mp.currency_contract
left join {{ ref('tokens_ethereum_nft') }} nft_tokens
    on nft_tokens.contract_address = mp.nft_contract_address
left join {{ source('prices', 'usd') }} as prices
    on prices.minute = date_trunc('minute', mp.block_time)
    and prices.contract_address = mp.currency_contract
    and prices.blockchain = 'ethereum'

