/// Comprehensive electronics brands and their models for the marketplace electronics listing.
/// Covers smartphones, computers, tablets, TVs, gaming, audio, cameras,
/// wearables, and home appliances — with global + African-market relevance.
class ElectronicsData {
  ElectronicsData._();

  /// All brands sorted alphabetically
  static List<String> get brands => _brandModels.keys.toList()..sort();

  /// Get models for a specific brand
  static List<String> getModels(String brand) {
    return _brandModels[brand] ?? [];
  }

  /// Standard storage options
  static const List<String> storageOptions = [
    '8GB',
    '16GB',
    '32GB',
    '64GB',
    '128GB',
    '256GB',
    '512GB',
    '1TB',
    '2TB',
    '4TB',
    '8TB',
  ];

  /// Standard RAM options
  static const List<String> ramOptions = [
    '2GB RAM',
    '3GB RAM',
    '4GB RAM',
    '6GB RAM',
    '8GB RAM',
    '12GB RAM',
    '16GB RAM',
    '32GB RAM',
    '64GB RAM',
    '128GB RAM',
  ];

  static const Map<String, List<String>> _brandModels = {
    // ══════════════════════════════════════════════════════════════════
    // SMARTPHONES & TABLETS
    // ══════════════════════════════════════════════════════════════════
    'Apple': [
      // iPhones
      'iPhone 16 Pro Max', 'iPhone 16 Pro', 'iPhone 16 Plus', 'iPhone 16',
      'iPhone 15 Pro Max', 'iPhone 15 Pro', 'iPhone 15 Plus', 'iPhone 15',
      'iPhone 14 Pro Max', 'iPhone 14 Pro', 'iPhone 14 Plus', 'iPhone 14',
      'iPhone 13 Pro Max', 'iPhone 13 Pro', 'iPhone 13', 'iPhone 13 Mini',
      'iPhone 12 Pro Max', 'iPhone 12 Pro', 'iPhone 12', 'iPhone 12 Mini',
      'iPhone SE (3rd Gen)', 'iPhone SE (2nd Gen)',
      'iPhone 11 Pro Max', 'iPhone 11 Pro', 'iPhone 11',
      'iPhone XS Max', 'iPhone XS', 'iPhone XR',
      'iPhone X', 'iPhone 8 Plus', 'iPhone 8',
      // iPads
      'iPad Pro 13"', 'iPad Pro 11"', 'iPad Air', 'iPad Mini', 'iPad',
      // Macs
      'MacBook Pro 16"', 'MacBook Pro 14"', 'MacBook Air 15"', 'MacBook Air 13"',
      'iMac 24"', 'Mac Mini', 'Mac Studio', 'Mac Pro',
      // Wearables
      'Apple Watch Ultra 2', 'Apple Watch Series 9', 'Apple Watch SE',
      // Audio
      'AirPods Pro 2', 'AirPods 4', 'AirPods 3', 'AirPods Max',
      // Other
      'Apple TV 4K', 'HomePod', 'HomePod Mini', 'Apple Vision Pro',
    ],
    'Samsung': [
      // Galaxy S Series
      'Galaxy S25 Ultra', 'Galaxy S25+', 'Galaxy S25',
      'Galaxy S24 Ultra', 'Galaxy S24+', 'Galaxy S24', 'Galaxy S24 FE',
      'Galaxy S23 Ultra', 'Galaxy S23+', 'Galaxy S23', 'Galaxy S23 FE',
      'Galaxy S22 Ultra', 'Galaxy S22+', 'Galaxy S22',
      'Galaxy S21 Ultra', 'Galaxy S21+', 'Galaxy S21', 'Galaxy S21 FE',
      'Galaxy S20 Ultra', 'Galaxy S20+', 'Galaxy S20', 'Galaxy S20 FE',
      // Galaxy Z Foldables
      'Galaxy Z Fold 6', 'Galaxy Z Fold 5', 'Galaxy Z Fold 4', 'Galaxy Z Fold 3',
      'Galaxy Z Flip 6', 'Galaxy Z Flip 5', 'Galaxy Z Flip 4', 'Galaxy Z Flip 3',
      // Galaxy A Series (very popular in Africa)
      'Galaxy A55', 'Galaxy A54', 'Galaxy A53', 'Galaxy A52',
      'Galaxy A35', 'Galaxy A34', 'Galaxy A33',
      'Galaxy A25', 'Galaxy A24', 'Galaxy A23',
      'Galaxy A15', 'Galaxy A14', 'Galaxy A13',
      'Galaxy A05s', 'Galaxy A05', 'Galaxy A04s', 'Galaxy A04',
      // Galaxy M Series
      'Galaxy M55', 'Galaxy M54', 'Galaxy M34', 'Galaxy M14',
      // Tablets
      'Galaxy Tab S9 Ultra', 'Galaxy Tab S9+', 'Galaxy Tab S9', 'Galaxy Tab S9 FE',
      'Galaxy Tab A9+', 'Galaxy Tab A9',
      // Laptops
      'Galaxy Book4 Ultra', 'Galaxy Book4 Pro 360', 'Galaxy Book4 Pro', 'Galaxy Book4',
      // Wearables
      'Galaxy Watch Ultra', 'Galaxy Watch 7', 'Galaxy Watch FE',
      'Galaxy Ring',
      // Audio
      'Galaxy Buds3 Pro', 'Galaxy Buds3', 'Galaxy Buds FE', 'Galaxy Buds2 Pro',
      // TVs
      'Neo QLED 8K', 'Neo QLED 4K', 'OLED S95D', 'Crystal UHD', 'The Frame', 'The Freestyle',
    ],
    'Google': [
      'Pixel 9 Pro XL', 'Pixel 9 Pro', 'Pixel 9', 'Pixel 9a',
      'Pixel 8 Pro', 'Pixel 8', 'Pixel 8a',
      'Pixel 7 Pro', 'Pixel 7', 'Pixel 7a',
      'Pixel 6 Pro', 'Pixel 6', 'Pixel 6a',
      'Pixel Fold', 'Pixel Tablet',
      'Pixel Watch 3', 'Pixel Watch 2',
      'Pixel Buds Pro 2', 'Pixel Buds A-Series',
      'Chromecast with Google TV', 'Nest Hub Max', 'Nest Hub',
      'Nest Wifi Pro', 'Nest Doorbell', 'Nest Cam',
    ],
    'OnePlus': [
      'OnePlus 13', 'OnePlus 12', 'OnePlus 12R',
      'OnePlus 11', 'OnePlus 11R', 'OnePlus 10 Pro', 'OnePlus 10T',
      'OnePlus Nord 4', 'OnePlus Nord CE 4', 'OnePlus Nord CE 4 Lite',
      'OnePlus Nord N30', 'OnePlus Nord N20',
      'OnePlus Open', 'OnePlus Pad 2', 'OnePlus Pad',
      'OnePlus Buds Pro 3', 'OnePlus Buds 3', 'OnePlus Watch 2',
    ],
    'Xiaomi': [
      'Xiaomi 14 Ultra', 'Xiaomi 14 Pro', 'Xiaomi 14',
      'Xiaomi 13 Ultra', 'Xiaomi 13 Pro', 'Xiaomi 13', 'Xiaomi 13T Pro', 'Xiaomi 13T',
      'Xiaomi 12 Pro', 'Xiaomi 12',
      // Redmi Note
      'Redmi Note 13 Pro+', 'Redmi Note 13 Pro', 'Redmi Note 13',
      'Redmi Note 12 Pro+', 'Redmi Note 12 Pro', 'Redmi Note 12',
      // Redmi
      'Redmi 13', 'Redmi 13C', 'Redmi 12', 'Redmi 12C',
      'Redmi A3', 'Redmi A2', 'Redmi A1',
      // POCO
      'POCO F6 Pro', 'POCO F6', 'POCO F5 Pro', 'POCO F5',
      'POCO X6 Pro', 'POCO X6', 'POCO X5 Pro',
      'POCO M6 Pro', 'POCO M6', 'POCO C65',
      // Tablets
      'Xiaomi Pad 6 Pro', 'Xiaomi Pad 6', 'Redmi Pad SE',
      // Audio & Wearables
      'Xiaomi Watch S3', 'Xiaomi Band 8', 'Xiaomi Buds 4 Pro',
    ],
    'Huawei': [
      'Mate 60 Pro+', 'Mate 60 Pro', 'Mate 60',
      'Mate 50 Pro', 'Mate 50',
      'P60 Pro', 'P60', 'P50 Pro', 'P50',
      'Nova 12 Ultra', 'Nova 12 Pro', 'Nova 12',
      'Nova 11 Pro', 'Nova 11', 'Nova 10 Pro', 'Nova Y91', 'Nova Y72', 'Nova Y61',
      'MatePad Pro 13.2"', 'MatePad Pro 11', 'MatePad Air', 'MatePad',
      'MateBook X Pro', 'MateBook 14s', 'MateBook 14', 'MateBook D16',
      'Watch GT 4', 'Watch 4 Pro', 'Watch Fit 3',
      'FreeBuds Pro 3', 'FreeBuds 5i',
      'Smart Screen SE 55"', 'Smart Screen V 75"',
    ],
    'Oppo': [
      'Find X7 Ultra', 'Find X7', 'Find X6 Pro',
      'Find N3 Flip', 'Find N3',
      'Reno 12 Pro', 'Reno 12', 'Reno 11 Pro', 'Reno 11', 'Reno 11 F',
      'Reno 10 Pro+', 'Reno 10 Pro', 'Reno 10',
      'A3 Pro', 'A3', 'A2', 'A1', 'A98', 'A78', 'A58', 'A38', 'A18',
      'Enco Air 3', 'Enco X2',
    ],
    'Vivo': [
      'X100 Ultra', 'X100 Pro', 'X100', 'X100s',
      'X90 Pro', 'X90',
      'V30 Pro', 'V30', 'V29 Pro', 'V29', 'V27 Pro',
      'Y200 Pro', 'Y200', 'Y100', 'Y36', 'Y28', 'Y18', 'Y03',
      'TWS Air', 'TWS 3 Pro',
    ],
    'Realme': [
      'GT 6', 'GT 5 Pro', 'GT 5', 'GT Neo 5',
      'Realme 12 Pro+', 'Realme 12 Pro', 'Realme 12',
      'Realme 11 Pro+', 'Realme 11 Pro', 'Realme 11',
      'Narzo 70 Pro', 'Narzo 70', 'Narzo 60 Pro',
      'C67', 'C55', 'C53', 'C33',
      'Realme Pad Mini', 'Realme Buds Air 5 Pro',
    ],
    'Motorola': [
      'Edge 50 Ultra', 'Edge 50 Pro', 'Edge 50 Fusion', 'Edge 50',
      'Edge 40 Pro', 'Edge 40 Neo', 'Edge 40',
      'Razr 50 Ultra', 'Razr 50', 'Razr 40 Ultra',
      'Moto G85', 'Moto G75', 'Moto G55', 'Moto G35', 'Moto G24',
      'Moto G Power', 'Moto G Stylus',
      'ThinkPhone',
    ],
    'Nokia': [
      'Nokia X30', 'Nokia G42', 'Nokia G22', 'Nokia G21',
      'Nokia C32', 'Nokia C22', 'Nokia C12', 'Nokia C02',
      'Nokia 105', 'Nokia 110', 'Nokia 8210',
    ],
    'Nothing': [
      'Nothing Phone (2a) Plus', 'Nothing Phone (2a)',
      'Nothing Phone (2)', 'Nothing Phone (1)',
      'Nothing Ear (2)', 'Nothing Ear (a)', 'Nothing Ear',
      'Nothing CMF Phone 1',
    ],

    // ── African-market smartphones ──
    'Tecno': [
      'Phantom X2 Pro', 'Phantom X2', 'Phantom V Fold', 'Phantom V Flip',
      'Camon 30 Premier', 'Camon 30 Pro', 'Camon 30',
      'Camon 20 Premier', 'Camon 20 Pro', 'Camon 20',
      'Spark 20 Pro+', 'Spark 20 Pro', 'Spark 20', 'Spark 20C',
      'Spark 10 Pro', 'Spark 10', 'Spark 10C',
      'Pova 6 Pro', 'Pova 6', 'Pova 5 Pro', 'Pova 5',
      'Pop 8', 'Pop 7 Pro', 'Pop 7',
    ],
    'Infinix': [
      'Zero 40', 'Zero 30', 'Zero 30 4G',
      'Note 40 Pro', 'Note 40', 'Note 30 Pro', 'Note 30',
      'Hot 40 Pro', 'Hot 40', 'Hot 40i', 'Hot 30', 'Hot 30i',
      'Smart 8 Plus', 'Smart 8', 'Smart 7',
      'GT 20 Pro',
    ],
    'itel': [
      'S24', 'S23+', 'S23',
      'P55+', 'P55', 'P40+', 'P40',
      'A70', 'A60s', 'A60', 'A58', 'A50',
      'it2170', 'it2160',
    ],

    // ══════════════════════════════════════════════════════════════════
    // COMPUTERS & LAPTOPS
    // ══════════════════════════════════════════════════════════════════
    'Dell': [
      'XPS 16', 'XPS 15', 'XPS 14', 'XPS 13',
      'Inspiron 16', 'Inspiron 15', 'Inspiron 14',
      'Latitude 7640', 'Latitude 5540', 'Latitude 3440',
      'Alienware m18', 'Alienware m16', 'Alienware x16', 'Alienware x14',
      'OptiPlex 7020', 'OptiPlex 3000',
      'Precision 7780', 'Precision 5690',
      'Dell U3423WE Monitor', 'Dell S2722QC Monitor',
    ],
    'HP': [
      'Spectre x360 16', 'Spectre x360 14',
      'Envy x360 16', 'Envy x360 15', 'Envy x360 14',
      'Pavilion 16', 'Pavilion 15', 'Pavilion 14',
      'EliteBook 860', 'EliteBook 840', 'ProBook 450',
      'OMEN 18', 'OMEN 16', 'OMEN 17',
      'Victus 16', 'Victus 15',
      'HP 255 G9', 'HP 250 G9',
      'HP DeskJet 2820e', 'HP LaserJet M140we',
    ],
    'Lenovo': [
      'ThinkPad X1 Carbon', 'ThinkPad X1 Yoga', 'ThinkPad T14s', 'ThinkPad T14',
      'ThinkPad E16', 'ThinkPad E14',
      'IdeaPad Pro 5', 'IdeaPad Slim 5', 'IdeaPad Flex 5', 'IdeaPad 3',
      'Yoga 9i', 'Yoga 7i', 'Yoga Book 9i',
      'Legion Pro 7i', 'Legion Pro 5i', 'Legion 5i', 'Legion Go',
      'Tab P12 Pro', 'Tab P11 Pro', 'Tab M11', 'Tab M10',
    ],
    'ASUS': [
      'ZenBook Pro 16X', 'ZenBook S 16', 'ZenBook 14', 'ZenBook S 13',
      'VivoBook Pro 16', 'VivoBook 15', 'VivoBook Go 15',
      'ROG Strix G18', 'ROG Strix G16', 'ROG Zephyrus G16', 'ROG Flow X16',
      'TUF Gaming A16', 'TUF Gaming A15',
      'ProArt Studiobook 16',
      'ROG Ally', 'ROG Phone 8 Pro', 'ROG Phone 8',
      'ZenFone 11 Ultra',
    ],
    'Acer': [
      'Swift Go 16', 'Swift Go 14', 'Swift X 14', 'Swift Edge 16',
      'Aspire 5', 'Aspire 3', 'Aspire Vero',
      'Predator Helios 18', 'Predator Helios 16', 'Predator Triton 17',
      'Nitro V 16', 'Nitro V 15',
      'Chromebook Plus 514', 'Chromebook 314',
    ],
    'MSI': [
      'Raider 18 HX', 'Raider GE78 HX', 'Raider GE76',
      'Stealth 18', 'Stealth 16', 'Stealth 14',
      'Creator Z16 HX', 'Creator M16',
      'Prestige 16', 'Prestige 14',
      'Titan 18 HX', 'Crosshair 16 HX',
      'Modern 15', 'Modern 14',
    ],
    'Microsoft': [
      'Surface Pro 10', 'Surface Pro 9', 'Surface Pro 8',
      'Surface Laptop 6', 'Surface Laptop 5', 'Surface Laptop Go 3',
      'Surface Laptop Studio 2', 'Surface Go 4',
      'Xbox Series X', 'Xbox Series S',
      'Xbox Wireless Controller',
    ],

    // ══════════════════════════════════════════════════════════════════
    // AUDIO
    // ══════════════════════════════════════════════════════════════════
    'Sony': [
      // Audio
      'WH-1000XM5', 'WH-1000XM4', 'WH-CH720N',
      'WF-1000XM5', 'WF-1000XM4',
      'LinkBuds S', 'LinkBuds',
      'ULT Wear', 'ULT Field 1', 'ULT Field 7',
      // Gaming
      'PlayStation 5', 'PlayStation 5 Slim', 'PlayStation 5 Digital',
      'PlayStation VR2', 'DualSense Edge',
      // Phones
      'Xperia 1 VI', 'Xperia 5 V', 'Xperia 10 VI',
      // Cameras
      'Alpha a7 IV', 'Alpha a7C II', 'Alpha a6700', 'ZV-E10 II', 'ZV-1 II',
      // TVs
      'Bravia XR A95L', 'Bravia XR X95L', 'Bravia 8', 'Bravia 9',
      // Audio systems
      'HT-A9', 'HT-A7000', 'HT-A5000',
    ],
    'Bose': [
      'QuietComfort Ultra Headphones', 'QuietComfort Headphones', 'QuietComfort 45',
      'QuietComfort Ultra Earbuds', 'QuietComfort Earbuds', 'QuietComfort Earbuds II',
      'Sport Open Earbuds',
      'SoundLink Max', 'SoundLink Flex', 'SoundLink Micro', 'SoundLink Mini II',
      'Portable Smart Speaker', 'Smart Soundbar 900', 'Smart Soundbar 600',
      'Bass Module 700', 'Surround Speakers 700',
    ],
    'JBL': [
      'Tour Pro 3', 'Tour One M2',
      'Live Pro 2', 'Live Beam 3', 'Live 660NC',
      'Tune 770NC', 'Tune Beam', 'Tune Flex',
      'Flip 6', 'Charge 5', 'Xtreme 4', 'Xtreme 3', 'Boombox 3',
      'Pulse 5', 'Go 4', 'Clip 4',
      'PartyBox 710', 'PartyBox 310', 'PartyBox Encore', 'PartyBox On-The-Go',
      'Bar 1300', 'Bar 1000', 'Bar 500',
    ],
    'Beats': [
      'Studio Pro', 'Studio3 Wireless',
      'Solo 4', 'Solo3 Wireless',
      'Fit Pro', 'Studio Buds+', 'Studio Buds',
      'Flex', 'Powerbeats Pro',
      'Pill',
    ],
    'Sennheiser': [
      'Momentum 4 Wireless', 'Momentum True Wireless 4',
      'Momentum Sport', 'HD 660S2', 'HD 560S',
      'Accentum Plus Wireless', 'Accentum Wireless',
      'TV Listener Set', 'Ambeo Soundbar Plus', 'Ambeo Mini',
    ],
    'Marshall': [
      'Major V', 'Major IV', 'Monitor III ANC', 'Monitor II ANC',
      'Motif II ANC', 'Minor IV',
      'Stanmore III', 'Acton III', 'Woburn III',
      'Emberton II', 'Willen II', 'Middleton',
    ],
    'Harman Kardon': [
      'Aura Studio 4', 'Onyx Studio 8', 'Go + Play 3',
      'Citation 300', 'SoundSticks 4', 'Fly TWS',
    ],
    'Sonos': [
      'Era 300', 'Era 100', 'Move 2', 'Roam 2',
      'Arc Ultra', 'Arc', 'Beam Gen 2', 'Ray',
      'Sub 4', 'Ace',
    ],
    'Bang & Olufsen': [
      'Beoplay H100', 'Beoplay HX', 'Beoplay H95',
      'Beoplay EX', 'Beoplay EQ',
      'Beosound A5', 'Beosound 2',
      'Beolab 28', 'Beovision Theatre',
    ],
    'Skullcandy': [
      'Crusher ANC 2', 'Hesh ANC', 'Hesh Evo',
      'Rail ANC', 'Smokin Buds', 'Sesh Evo',
      'Push Active', 'Indy Evo',
    ],

    // ══════════════════════════════════════════════════════════════════
    // GAMING
    // ══════════════════════════════════════════════════════════════════
    'Nintendo': [
      'Switch 2', 'Switch OLED', 'Switch Lite', 'Switch',
    ],
    'Valve': ['Steam Deck OLED', 'Steam Deck', 'Steam Link'],
    'Razer': [
      'Blade 18', 'Blade 16', 'Blade 15', 'Blade 14',
      'BlackWidow V4', 'Huntsman V3',
      'DeathAdder V3', 'Viper V3 Pro', 'Basilisk V3',
      'BlackShark V2 Pro', 'Kraken V4',
      'Kishi Ultra',
    ],
    'Logitech': [
      'G Pro X Superlight 2', 'G502 X Plus', 'G502 X Lightspeed',
      'G Pro X TKL', 'G915 TKL', 'G915 X',
      'G Pro X 2 Lightspeed Headset', 'G735',
      'Streamcam', 'Brio 4K',
      'MX Master 3S', 'MX Keys S', 'MX Anywhere 3S',
      'Ergo M575', 'K380', 'K780',
    ],
    'SteelSeries': [
      'Arctis Nova Pro Wireless', 'Arctis Nova 7',
      'Aerox 5 Wireless', 'Prime Mini Wireless',
      'Apex Pro TKL', 'Apex 9 TKL',
    ],
    'Corsair': [
      'K100 RGB', 'K70 Max', 'K65 Plus',
      'Scimitar Elite Wireless', 'Dark Core RGB Pro',
      'Virtuoso RGB Wireless XT', 'HS80 RGB Wireless',
      'iCUE Link H150i', 'Elgato Stream Deck',
    ],

    // ══════════════════════════════════════════════════════════════════
    // CAMERAS & DRONES
    // ══════════════════════════════════════════════════════════════════
    'Canon': [
      'EOS R1', 'EOS R5 Mark II', 'EOS R5', 'EOS R6 Mark II',
      'EOS R8', 'EOS R50', 'EOS R100',
      'EOS 90D', 'EOS 250D',
      'PowerShot V10', 'PowerShot G7X Mark III',
      'PIXMA G3270', 'PIXMA TR4720',
    ],
    'Nikon': [
      'Z8', 'Z9', 'Z7 II', 'Z6 III', 'Z5',
      'Zf', 'Z50', 'Z30',
      'D850', 'D7500', 'D5600',
      'Coolpix P1000',
    ],
    'GoPro': [
      'HERO13 Black', 'HERO12 Black', 'HERO11 Black',
      'HERO11 Mini', 'MAX',
    ],
    'DJI': [
      'Mavic 3 Pro', 'Mavic 3 Classic', 'Air 3', 'Mini 4 Pro', 'Mini 3',
      'Osmo Pocket 3', 'Osmo Action 5 Pro', 'Osmo Action 4',
      'Avata 2', 'FPV',
      'Ronin RS 4', 'Ronin RS 3 Mini',
      'DJI Mic 2',
    ],
    'Fujifilm': [
      'X-T5', 'X-T50', 'X-H2S', 'X-H2',
      'X-S20', 'X-S10', 'X-E4',
      'X100VI', 'X100V',
      'GFX 100 II', 'GFX 50S II',
      'Instax Mini 12', 'Instax Mini Evo', 'Instax Wide 400',
    ],
    'Panasonic': [
      'Lumix S5 II', 'Lumix S5 IIX', 'Lumix S1H',
      'Lumix GH6', 'Lumix GH7', 'Lumix G9 II',
    ],
    'Insta360': [
      'X4', 'X3', 'ONE RS', 'Ace Pro', 'Ace', 'GO 3S', 'Flow Pro',
    ],

    // ══════════════════════════════════════════════════════════════════
    // TVs & DISPLAYS
    // ══════════════════════════════════════════════════════════════════
    'LG': [
      // TVs
      'OLED G4', 'OLED C4', 'OLED B4', 'OLED M4',
      'QNED 99T', 'QNED 90T', 'QNED 85T',
      'NanoCell 85', 'NanoCell 75', 'UHD UT80',
      // Monitors
      'UltraGear 45GS96QB', 'UltraGear 32GS95UE', 'UltraFine 5K',
      // Laptops
      'gram 17', 'gram 16', 'gram 15',
      // Audio
      'Tone Free T90S', 'Tone Free FP9', 'Tone Free FP8',
      // Soundbars
      'SC9S', 'SP7Y', 'SN5Y',
      // Appliances
      'InstaView Refrigerator', 'WashTower', 'CordZero A9 Kompressor',
      'PuriCare Air Purifier',
    ],
    'Hisense': [
      // TVs
      'ULED X 110"', 'U8N 65"', 'U8N 55"', 'U7N 75"', 'U7N 65"',
      'U6N 65"', 'U6N 55"', 'A7N 65"', 'A6N 55"',
      'Laser TV 120L5 Series',
      // Appliances
      'Side-by-Side Refrigerator', 'Top Mount Fridge',
      'Front Load Washer', 'Window AC', 'Portable AC',
      'Microwave Oven',
    ],
    'TCL': [
      'QM8 98"', 'QM8 85"', 'Q7 75"', 'Q7 65"',
      'Q6 65"', 'Q6 55"', 'S4 43"', 'S3 32"',
      'NXTPAPER 14 Pro', 'Tab 11 Gen 2',
      'AC Window Unit', 'AC Split Unit',
    ],
    'Skyworth': [
      'S9A OLED', 'G6 61"', 'G3 50"',
      'UB7500 55"', 'UB7500 43"',
      'TB7000 40"', 'E3D 32"',
    ],
    'Vitron': [
      'HTC 3246', 'HTC 4368FS', 'HTC 5568US',
    ],
    'Syinix': [
      'A51 Series 43"', 'A51 Series 32"',
      'U61 Series 55"', 'U61 Series 50"',
    ],

    // ══════════════════════════════════════════════════════════════════
    // HOME APPLIANCES & LIFESTYLE
    // ══════════════════════════════════════════════════════════════════
    'Dyson': [
      'V15 Detect', 'V12 Detect Slim', 'V11', 'V8',
      'Airwrap', 'Supersonic', 'Airstrait', 'Corrale',
      'Pure Cool', 'Hot+Cool', 'Purifier Big Quiet',
      'Zone', 'Solarcycle Morph',
    ],
    'Defy': [
      'Automaid Washing Machine', 'AquaWave Washing Machine',
      'Manhattan Fridge', 'Side-by-Side Fridge',
      'Gemini Stove', 'Slimline Stove',
      'Multifunction Oven', 'Air Fryer',
      'Dishwasher', 'Tumble Dryer', 'Microwave',
    ],
    'Bosch': [
      'Series 8 Washing Machine', 'Series 6 Washing Machine',
      'KGN Series Fridge', 'Side-by-Side Fridge',
      'Dishwasher SMS6', 'Dishwasher SMV4',
      'Gas Hob PPH6', 'Oven HBG6',
      'Unlimited Vacuum',
    ],
    'Haier': [
      'French Door Fridge', 'Bottom Mount Fridge', 'Mini Fridge',
      'Front Load Washer', 'Top Load Washer',
      'Window AC', 'Split AC', 'Portable AC',
      'LED TV LE32', 'LED TV LE43',
    ],
    'Midea': [
      'Side-by-Side Fridge', 'Top Mount Fridge',
      'Front Loader Washer', 'Top Loader Washer',
      'Split AC Xtreme', 'Window AC',
      'Dishwasher', 'Microwave',
    ],
    'Whirlpool': [
      'French Door Fridge', 'Side-by-Side Fridge',
      'Front Load Washer', 'Top Load Washer',
      'Dishwasher', 'Microwave', 'Oven',
    ],

    // ══════════════════════════════════════════════════════════════════
    // NETWORKING & SMART HOME
    // ══════════════════════════════════════════════════════════════════
    'TP-Link': [
      'Deco XE75', 'Deco X55', 'Deco M5',
      'Archer AXE75', 'Archer AX73', 'Archer AX21',
      'Tapo C520WS', 'Tapo C200', 'Tapo L530E',
    ],
    'Amazon': [
      'Echo Show 15', 'Echo Show 8', 'Echo Show 5',
      'Echo Dot 5th Gen', 'Echo Pop',
      'Fire TV Stick 4K Max', 'Fire TV Stick 4K', 'Fire TV Stick Lite',
      'Fire HD 10', 'Fire HD 8',
      'Kindle Paperwhite', 'Kindle Scribe', 'Kindle',
      'Ring Video Doorbell 4', 'Ring Indoor Cam',
      'Blink Outdoor 4', 'Blink Mini',
    ],

    // ══════════════════════════════════════════════════════════════════
    // OTHER ELECTRONICS
    // ══════════════════════════════════════════════════════════════════
    'Anker': [
      'Soundcore Motion X600', 'Soundcore Space One', 'Soundcore P40i',
      'PowerCore 26800', 'PowerCore 10000', 'PowerCore III Elite',
      'Nebula Capsule 3', 'Nebula Cosmos 4K',
      'eufy RoboVac', 'eufy Clean X9 Pro',
    ],
    'Garmin': [
      'Fenix 8', 'Fenix 7X', 'Forerunner 965', 'Forerunner 265',
      'Venu 3', 'Venu Sq 2',
      'vívoactive 5', 'Enduro 3',
      'Edge 1050', 'Edge 540',
    ],
    'Fitbit': [
      'Sense 2', 'Versa 4', 'Charge 6', 'Luxe', 'Inspire 3',
    ],
    'Meta': [
      'Quest 3', 'Quest 3S', 'Quest 2',
      'Ray-Ban Meta Smart Glasses',
    ],
    'Oraimo': [
      'FreePods 4', 'FreePods 3', 'SpaceBuds Z',
      'Riff 2', 'BoomPop 2',
      'PowerBank 20000mAh', 'PowerBank 10000mAh',
      'SmartWatch Tempo S2', 'SmartWatch OSW-16',
    ],
    'Epson': [
      'EcoTank L3250', 'EcoTank L3210', 'EcoTank L1250',
      'WorkForce WF-2930', 'Expression Home XP-4200',
      'EpiqVision Mini EF12', 'Pro EX11000',
    ],
    'Brother': [
      'DCP-T426W', 'DCP-T220', 'MFC-L2750DW',
      'HL-L2350DW', 'HL-L3270CDW',
    ],
  };
}
