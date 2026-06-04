/// Comprehensive motorcycle & three-wheeler brands and their models.
/// Covers sport bikes, cruisers, adventure, scooters, electric,
/// popular African-market brands (boda-boda / okada / pikipiki), and
/// tricycles / tuk-tuks / auto-rickshaws (keke napep) used across
/// Africa, Asia, and the Philippines.
class MotorcycleData {
  MotorcycleData._();

  /// All brands sorted alphabetically
  static List<String> get brands => _brandModels.keys.toList()..sort();

  /// Get models for a specific brand
  static List<String> getModels(String brand) {
    return _brandModels[brand] ?? [];
  }

  /// Engine size options (cc)
  static const List<String> engineSizes = [
    '50cc',
    '100cc',
    '110cc',
    '125cc',
    '150cc',
    '200cc',
    '250cc',
    '300cc',
    '400cc',
    '500cc',
    '600cc',
    '650cc',
    '700cc',
    '750cc',
    '800cc',
    '900cc',
    '1000cc',
    '1100cc',
    '1200cc',
    '1300cc',
    '1400cc',
    '1500cc',
    '1600cc',
    '1800cc',
    '2000cc+',
  ];

  /// Motorcycle types
  static const List<String> motorcycleTypes = [
    'Sport / Supersport',
    'Naked / Street',
    'Cruiser',
    'Touring',
    'Adventure / Dual-Sport',
    'Enduro / Off-Road',
    'Scooter',
    'Underbone / Cub',
    'Standard / Commuter',
    'Cafe Racer',
    'Chopper / Custom',
    'Electric',
    'Tricycle / Tuk-Tuk',
    'Trike',
    'Other',
  ];

  static const Map<String, List<String>> _brandModels = {
    // ══════════════════════════════════════════════════════════════════
    // JAPANESE BIG FOUR
    // ══════════════════════════════════════════════════════════════════
    'Honda': [
      // Sport
      'CBR1000RR-R Fireblade', 'CBR600RR', 'CBR500R', 'CBR300R', 'CBR250RR',
      'CBR150R', 'CBR125R',
      // Naked / Street
      'CB1000R', 'CB650R', 'CB500F', 'CB300R', 'CB125R',
      'Hornet 750', 'Hornet 600',
      // Adventure
      'Africa Twin CRF1100L', 'Transalp XL750', 'CB500X', 'NX500',
      'CRF300L', 'CRF300 Rally', 'CRF250L',
      // Touring
      'Gold Wing', 'Gold Wing Tour', 'NT1100',
      // Cruiser
      'Rebel 1100', 'Rebel 500', 'Rebel 300',
      'Shadow 750', 'Shadow Phantom',
      // Commuter / African market
      'CG 125', 'CG 150', 'CB125F', 'CB110', 'Ace 125', 'Ace 110',
      'TMX 125', 'XRM 125', 'Wave 110', 'Wave 125',
      'Navi', 'Dio', 'Click 125i', 'Click 160',
      // Scooter
      'PCX 160', 'PCX 125', 'ADV 160', 'ADV 150',
      'Forza 350', 'Forza 750',
      'SH 350', 'SH 150i', 'SH Mode',
      // Electric
      'EM1 e:', 'U-Go',
    ],
    'Yamaha': [
      // Sport
      'YZF-R1', 'YZF-R1M', 'YZF-R7', 'YZF-R6', 'YZF-R3', 'YZF-R15',
      'YZF-R125',
      // Naked / Street
      'MT-10', 'MT-09', 'MT-07', 'MT-03', 'MT-125', 'MT-15',
      'XSR900', 'XSR700', 'XSR125',
      // Adventure
      'Ténéré 700', 'Ténéré 700 Rally', 'Tracer 9', 'Tracer 7',
      // Touring
      'FJR1300',
      // Cruiser
      'Bolt', 'V Star 250', 'VMAX',
      // Commuter (African market)
      'YBR 125', 'YBR 125G', 'Crux Rev', 'Saluto 125',
      'FZ-S FI', 'FZS 25', 'Fazer 25',
      // Scooter
      'XMAX 300', 'NMAX 155', 'NMAX 125',
      'Aerox 155', 'Jog 125', 'Fascino 125',
      // Off-road
      'WR250F', 'WR450F', 'YZ250F', 'YZ450F',
      // Electric
      'E01', 'Neo\'s',
    ],
    'Suzuki': [
      // Sport
      'GSX-R1000R', 'GSX-R750', 'GSX-R600', 'GSX-250R',
      'Hayabusa',
      // Naked / Street
      'GSX-S1000', 'GSX-S750', 'GSX-S125',
      'SV650', 'Katana',
      // Adventure
      'V-Strom 1050', 'V-Strom 800DE', 'V-Strom 650', 'V-Strom 250',
      // Touring
      'Burgman 400', 'Burgman 200',
      // Cruiser
      'Boulevard M109R', 'Boulevard S40', 'Boulevard C50',
      // Commuter (African market)
      'GN 125', 'EN 125', 'GS 150', 'Gixxer 150', 'Gixxer SF 250',
      'Intruder 150', 'Access 125', 'Avenis 125',
      // Scooter
      'Address 110', 'Lets',
      // Off-road
      'DR-Z400', 'RM-Z250', 'RM-Z450',
    ],
    'Kawasaki': [
      // Sport
      'Ninja ZX-10R', 'Ninja ZX-10RR', 'Ninja ZX-6R',
      'Ninja ZX-4RR', 'Ninja 400', 'Ninja 300', 'Ninja 125',
      // Naked / Street
      'Z H2', 'Z900', 'Z650', 'Z400', 'Z125',
      // Adventure
      'Versys 1000', 'Versys 650', 'Versys-X 300', 'KLR 650',
      'KLX 300', 'KLX 230', 'KLX 140',
      // Touring
      'Concours 14', 'Vulcan S',
      // Cruiser
      'Vulcan 900 Classic', 'Vulcan 1700', 'Eliminator 500', 'Eliminator 400',
      // Retro
      'W800', 'Meguro S1',
      // Sport Touring
      'Ninja 1000SX',
      // Electric
      'Ninja e-1', 'Z e-1',
    ],

    // ══════════════════════════════════════════════════════════════════
    // EUROPEAN
    // ══════════════════════════════════════════════════════════════════
    'BMW': [
      // Sport
      'S 1000 RR', 'S 1000 R', 'M 1000 RR', 'M 1000 R',
      // Adventure
      'R 1300 GS', 'R 1300 GS Adventure', 'R 1250 GS', 'R 1250 GS Adventure',
      'F 900 GS', 'F 900 GS Adventure', 'F 800 GS',
      'G 310 GS', 'F 750 GS',
      // Naked
      'R 1250 R', 'F 900 R', 'G 310 R',
      // Touring
      'K 1600 GTL', 'K 1600 GT', 'K 1600 Grand America',
      'R 1250 RT',
      // Heritage
      'R nineT', 'R nineT Scrambler', 'R 18', 'R 18 Transcontinental',
      // Scooter
      'C 400 X', 'C 400 GT', 'CE 04',
    ],
    'Ducati': [
      'Panigale V4',
      'Panigale V4 S',
      'Panigale V4 R',
      'Panigale V2',
      'Streetfighter V4',
      'Streetfighter V4 S',
      'Streetfighter V2',
      'Monster',
      'Monster SP',
      'Monster 937',
      'Multistrada V4',
      'Multistrada V4 Rally',
      'Multistrada V4 S',
      'Multistrada V2',
      'DesertX',
      'DesertX Rally',
      'Diavel V4',
      'XDiavel',
      'Hypermotard 950',
      'Hypermotard 698 Mono',
      'Scrambler 800',
      'Scrambler 1100',
    ],
    'KTM': [
      // Sport
      'RC 390', 'RC 200', 'RC 125',
      // Naked
      '1390 Super Duke R',
      '890 Duke R',
      '790 Duke',
      '390 Duke',
      '200 Duke',
      '125 Duke',
      // Adventure
      '1390 Super Adventure S', '1290 Super Adventure R',
      '890 Adventure R', '790 Adventure',
      '390 Adventure', '250 Adventure',
      // Enduro / Off-road
      '300 EXC TPI', '250 EXC-F', '500 EXC-F',
      '350 SX-F', '450 SX-F', '250 SX-F',
      // Motocross
      '450 SX-F Factory', '250 SX',
      // Electric
      'Freeride E-XC',
    ],
    'Aprilia': [
      'RSV4',
      'RSV4 Factory',
      'RS 660',
      'RS 457',
      'RS 125',
      'Tuono V4',
      'Tuono 660',
      'Tuareg 660',
      'Tuareg Rally',
      'Shiver 900',
      'Dorsoduro 900',
      'SR GT 200',
      'SR GT 125',
      'SXR 160',
    ],
    'Husqvarna': [
      'Norden 901',
      'Norden 901 Expedition',
      'Svartpilen 801',
      'Svartpilen 401',
      'Svartpilen 125',
      'Vitpilen 401',
      'Vitpilen 125',
      'FE 450',
      'FE 350',
      'TE 300i',
      'FC 450',
      'FC 350',
      'FC 250',
    ],
    'Triumph': [
      // Sport
      'Daytona 660', 'Speed Triple 1200 RS', 'Speed Triple 1200 RR',
      // Adventure
      'Tiger 1200 Rally', 'Tiger 1200 GT', 'Tiger 900 Rally', 'Tiger 900 GT',
      'Tiger Sport 660',
      // Naked
      'Street Triple RS', 'Street Triple R', 'Street Triple S',
      'Trident 660', 'Speed 400',
      // Cruiser
      'Rocket 3', 'Thunderbird',
      // Classic / Heritage
      'Bonneville T120', 'Bonneville T100', 'Bonneville Bobber',
      'Thruxton RS', 'Speed Twin 1200', 'Speed Twin 900',
      'Scrambler 1200', 'Scrambler 900', 'Scrambler 400 X',
    ],
    'MV Agusta': [
      'F3 800',
      'F3 RR',
      'Superveloce',
      'Brutale 1000 RR',
      'Brutale 800',
      'Dragster 800',
      'Dragster RR',
      'Turismo Veloce 800',
      'Lucky Explorer 5.5',
    ],
    'Moto Guzzi': [
      'V100 Mandello',
      'V85 TT',
      'V7 Stone',
      'V9 Bobber',
      'Stelvio',
    ],
    'Vespa': [
      'GTS Super 300',
      'GTS 300',
      'Sprint 150',
      'Sprint 125',
      'Primavera 150',
      'Primavera 125',
      'Elettrica',
    ],
    'Piaggio': [
      'MP3 530 HPE', 'MP3 400 HPE', 'Beverly 400',
      'Medley 150', 'Liberty 150',
      // Three-wheelers — Ape series, dominant in Africa, India & S. America
      'Ape City', 'Ape City+', 'Ape Classic', 'Ape Auto DX',
      'Ape HT DX', 'Ape Xtra DLX', 'Ape Xtra LDX+',
      'Ape Electrik', 'Ape E-City', 'Ape E-Xtra',
      'Ape NXT', 'Ape NXT+',
    ],

    // ══════════════════════════════════════════════════════════════════
    // AMERICAN
    // ══════════════════════════════════════════════════════════════════
    'Harley-Davidson': [
      // Touring
      'Road Glide', 'Street Glide', 'Ultra Limited', 'Electra Glide',
      'Road King', 'Road King Special',
      // Cruiser / Softail
      'Fat Boy', 'Heritage Classic', 'Breakout', 'Fat Bob',
      'Softail Standard', 'Sport Glide', 'Low Rider', 'Low Rider S',
      'Low Rider ST', 'Street Bob',
      // Sportster
      'Sportster S', 'Nightster', 'Iron 883', 'Forty-Eight',
      // Adventure
      'Pan America 1250', 'Pan America 1250 Special',
      // CVO
      'CVO Road Glide', 'CVO Street Glide',
      // Electric
      'LiveWire ONE',
    ],
    'Indian': [
      'Chieftain',
      'Chief',
      'Chief Dark Horse',
      'Super Chief',
      'Scout',
      'Scout Bobber',
      'Scout Rogue',
      'Sport Chief',
      'Challenger',
      'Roadmaster',
      'Pursuit',
      'FTR',
      'FTR Rally',
      'FTR S',
    ],
    'Polaris': ['Slingshot S', 'Slingshot R', 'Slingshot SL'],
    'Buell': ['Hammerhead 1190RX', 'Super Cruiser'],

    // ══════════════════════════════════════════════════════════════════
    // CHINESE / AFRICAN MARKET (Boda-boda, Okada)
    // ══════════════════════════════════════════════════════════════════
    'Bajaj': [
      // Very popular in Africa (Kenya, Nigeria, Tanzania)
      'Boxer 150', 'Boxer 125', 'Boxer 100',
      'CT 125', 'CT 110', 'CT 100',
      'Pulsar NS200', 'Pulsar NS160', 'Pulsar 150', 'Pulsar 125',
      'Dominar 400', 'Dominar 250',
      'Avenger 220', 'Avenger 160',
      'Discover 125', 'Discover 110', 'Platina 110',
      'Chetak', // Electric scooter
      // Three-wheelers (tuk-tuk / auto-rickshaw / keke napep)
      'RE Compact 4S', 'RE 4S Petrol', 'RE 4S Diesel', 'RE 4S LPG',
      'RE 4S CNG', 'RE Maxima Z', 'RE Maxima Cargo', 'RE Maxima X Wide',
      'Qute', // Quadricycle / micro-car
      'GoGo', // Electric three-wheeler
    ],
    'TVS': [
      // Popular in East & West Africa
      'Apache RTR 200', 'Apache RTR 180', 'Apache RTR 160',
      'Apache RR 310',
      'Star City+ 125', 'Star City 110',
      'Sport 100', 'Radeon 110',
      'HLX 150', 'HLX 125', 'HLX 100',
      'Jupiter 125', 'Jupiter 110', 'Ntorq 125', 'Scooty Pep+',
      // Three-wheelers — "King" is hugely popular across 60+ countries
      'King Deluxe', 'King Deluxe Plus', 'King TG', 'King Diesel',
      'King CNG', 'King Electric', 'King Duramax',
    ],
    'Hero': [
      'XPulse 200 4V',
      'XPulse 200',
      'XPulse 200T',
      'Xtreme 160R',
      'Xtreme 125R',
      'Glamour 125',
      'Splendor Plus',
      'Splendor iSmart',
      'Super Splendor',
      'HF Deluxe',
      'HF 100',
      'CD 110 Dream',
      'Passion Plus',
      'Maestro Edge 125',
      'Pleasure Plus 110',
    ],
    'Royal Enfield': [
      'Himalayan 450',
      'Himalayan 411',
      'Interceptor 650',
      'Continental GT 650',
      'Super Meteor 650',
      'Meteor 350',
      'Hunter 350',
      'Classic 350',
      'Bullet 350',
      'Scram 411',
    ],
    'CFMoto': [
      'CL-X 700',
      'CL-X 700 Heritage',
      '700MT',
      '800MT',
      '800MT Touring',
      '300NK',
      '250NK',
      '300SR',
      '250SR',
      '450SR',
      '650NK',
      '650GT',
    ],
    'Zontes': [
      '350T',
      '350D',
      '350R',
      '350E',
      '310R',
      '310T',
      '310X',
      '155U',
      '155G',
    ],
    'Benelli': [
      'TRK 702',
      'TRK 502',
      'TRK 502 X',
      'Leoncino 500',
      'Leoncino 250',
      '752S',
      '502C',
      'TNT 135',
      'TNT 25',
      'TNT 249S',
    ],
    'SYM': [
      'Maxsym TL',
      'Cruisym 300',
      'Joymax Z 300',
      'NH-T 200',
      'NH-X 125',
      'Fiddle 200',
      'Fiddle 125',
      'Orbit III 125',
      'Symphony 150',
    ],
    'Lifan': [
      'KPV 150',
      'KP Mini 150',
      'KP 200',
      'KPS 200',
      'V16',
      'LF 150-2J',
      'LF 200-GY',
      'LF 125-GY',
    ],
    'Sinnis': [
      'RSX 125',
      'GPX 125',
      'Apache 125',
      'Hoodlum 125',
      'Terrain 125',
      'Bomber 125',
    ],
    'Haojue': [
      // Suzuki's Chinese partner, very popular in West Africa
      'DR 160', 'GN 125', 'EN 150',
      'NK 150', 'KA 135',
      'Lucky Plus', 'Cool 110',
      'UH 125', 'UY 125',
    ],
    'Daylong': [
      'DY 150-6',
      'DY 125-8',
      'DY 110',
      'DY 200 Cargo',
      'DY 150 Cargo',
    ],
    'Apsonic': ['AP 150', 'AP 125', 'AP 110', 'Zone 125', 'Aloba 200'],
    'Qingqi': ['QM 200', 'QM 150', 'QM 125', 'QM 110', 'QM 100'],
    'Shineray': ['XY 200', 'XY 150 Cargo', 'XY 125', 'XY 150-10D', 'XY 200-IG'],
    'Captain': ['CP 150', 'CP 125', 'CP 110', 'CP 200 Cargo'],
    'Jincheng': ['JC 110', 'JC 125-8', 'JC 150 GY', 'JC 200'],

    // ══════════════════════════════════════════════════════════════════
    // THREE-WHEELER / TRICYCLE / TUK-TUK BRANDS
    // ══════════════════════════════════════════════════════════════════
    'Atul Auto': [
      // Major Indian 3-wheeler manufacturer — strong presence in Africa
      'Gemini Petrol', 'Gemini Diesel', 'Gemini LPG', 'Gemini CNG',
      'Gem Paxx', 'Gem Cargo', 'Elite Plus',
      'Rio', 'Rio+', 'Rik',
      'Smart E-Rickshaw',
    ],
    'Mahindra': [
      // Mahindra Last Mile Mobility — leading EV 3-wheelers in India
      'Treo Zor', 'Treo Plus', 'Treo SFT',
      'Treo Yaari', 'Treo Auto',
      'eAlfa Mini', 'eAlfa Cargo', 'eAlfa Super',
      'Alfa Passenger', 'Alfa Load Carrier',
      'Alfa CNG',
    ],
    'Jinpeng': [
      // Largest Chinese electric 3-wheeler manufacturer
      'DK', 'DK3', 'DK5', 'DKLK',
      'TL 150', 'TR 250',
      'Cargo E-Trike 1000W', 'Cargo E-Trike 1500W',
      'Passenger E-Trike',
    ],
    'Huaihai': [
      // Major Chinese three-wheeler group — exports to Africa & SE Asia
      'Zong Shen Passenger', 'Cargo K3', 'Cargo K7',
      'E-Trike QC1', 'E-Trike QC3',
      'H5 Electric', 'H7 Electric',
      'Mini Tuk-Tuk',
    ],
    'Zongshen': [
      // Chinese — huge 3-wheeler exporter to Africa
      'ZS 200 Tricycle', 'ZS 250 Tricycle', 'ZS 150 Cargo',
      'ZS 200 Cargo', 'ZS 300 Cargo',
      'E-Trike Passenger', 'E-Trike Cargo',
    ],
    'Loncin': [
      // Major Chinese manufacturer — popular in West Africa
      'LX 200 Trike', 'LX 250 Trike', 'LX 150 Cargo',
      'LX 200 Cargo', 'LX 300 Cargo',
      'Electric Passenger Trike',
    ],
    'Terra Motors': [
      // Japanese EV three-wheelers — popular in SE Asia & Philippines
      'Y4A', 'Y6A', 'Y8A',
      'Y4 Cargo',
      'R6', 'R8',
    ],
    'BEMAC': [
      // Philippines-based electric tricycle manufacturer
      'e-Trike Passenger', 'e-Trike Cargo',
      'e-Jeep',
    ],
    'Innoson': [
      // Nigerian manufacturer — assembles keke napep locally
      'IVM Keke', 'IVM Cargo Tricycle',
      'IVM Passenger Tricycle',
    ],
    'Kinetic Green': [
      // Indian EV specialist — e-rickshaws
      'Safar Smart', 'Safar Shakti', 'Safar Star',
      'Safar Jumbo',
      'KineticGreen E-Auto',
    ],
    'Baxy': [
      // Indian auto-rickshaw maker
      'Express', 'Express G', 'Express M-Tec',
      'CEL E-Rath', 'CEL Beat',
    ],
    'Lohia Auto': [
      // Indian e-rickshaw manufacturer
      'Comfort Plus', 'Comfort DLX',
      'Narain DLX', 'Narain Gold',
      'Humrahi E-Cart',
    ],
    'NWOW': [
      // Filipino electric vehicle brand
      'WOW ERV Electric Tricycle', 'WOW EV Two-Seater',
      'NWOW E-Trike',
    ],
    'Simba': [
      // Nigerian 3-wheeler brand (TVS assembly partner)
      'Simba King', 'Simba King Deluxe',
      'Simba CNG',
    ],

    // ══════════════════════════════════════════════════════════════════
    // ELECTRIC MOTORCYCLES
    // ══════════════════════════════════════════════════════════════════
    'Zero': ['SR/F', 'SR/S', 'SR', 'DSR/X', 'DS', 'FX', 'S', 'FXE'],
    'Energica': ['Ego+', 'Eva Ribelle', 'Experia'],
    'LiveWire': ['S2 Del Mar', 'S2 Mulholland', 'ONE'],
    'Super SOCO': ['TC Max', 'TC', 'TS Street Hunter', 'CUx', 'CPx', 'TSx'],
    'NIU': [
      'KQi3 Pro',
      'KQi3 Max',
      'KQi2 Pro',
      'NQi GT',
      'MQi+',
      'MQi Sport',
      'Gova G0',
      'Gova C0',
    ],
    'Spiro': [
      // Popular electric boda-boda in East Africa
      'Spiro Go', 'Spiro Move',
    ],
    'Roam': [
      // Kenyan electric motorcycle company
      'Roam Air',
    ],
    'ARC': ['Vector'],
    'Damon': ['HyperSport', 'HyperFighter'],
  };
}
