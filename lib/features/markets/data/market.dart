enum MarketStatus { active, planned }

class Market {
  const Market({
    required this.code,
    required this.name,
    required this.currency,
    required this.timezone,
    required this.status,
  });

  final String code;
  final String name;
  final String currency;
  final String timezone;
  final MarketStatus status;
}

/// Mirrors GET /v1/markets. Zimbabwe launches first; the rest are config-led.
const markets = [
  Market(
    code: 'ZW',
    name: 'Zimbabwe',
    currency: 'USD',
    timezone: 'Africa/Harare',
    status: MarketStatus.active,
  ),
  Market(
    code: 'BW',
    name: 'Botswana',
    currency: 'BWP',
    timezone: 'Africa/Gaborone',
    status: MarketStatus.planned,
  ),
  Market(
    code: 'ZA',
    name: 'South Africa',
    currency: 'ZAR',
    timezone: 'Africa/Johannesburg',
    status: MarketStatus.planned,
  ),
  Market(
    code: 'AE',
    name: 'UAE / Dubai',
    currency: 'AED',
    timezone: 'Asia/Dubai',
    status: MarketStatus.planned,
  ),
];

const activeMarket = Market(
  code: 'ZW',
  name: 'Zimbabwe',
  currency: 'USD',
  timezone: 'Africa/Harare',
  status: MarketStatus.active,
);
