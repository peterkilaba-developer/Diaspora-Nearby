/// Comprehensive car brands and their models for the marketplace vehicle listing.
/// Covers mainstream, luxury, African-market, Asian, European, American,
/// Chinese, and commercial brands with full international model ranges.
class VehicleData {
  VehicleData._();

  /// All brands sorted alphabetically
  static List<String> get brands => _brandModels.keys.toList()..sort();

  /// Get models for a specific brand
  static List<String> getModels(String brand) {
    return _brandModels[brand] ?? [];
  }

  static const Map<String, List<String>> _brandModels = {
    // ── A ──
    'Acura': [
      'ILX', 'Integra', 'MDX', 'NSX', 'RDX', 'TLX', 'ZDX',
    ],
    'Alfa Romeo': [
      '4C', '147', '156', '159', 'Brera', 'Giulia', 'Giulietta',
      'MiTo', 'Spider', 'Stelvio', 'Tonale',
    ],
    'Aston Martin': [
      'DB11', 'DB12', 'DBS', 'DBX', 'DBX707',
      'Valhalla', 'Vanquish', 'Vantage',
    ],
    'Audi': [
      'A1', 'A3', 'A4', 'A5', 'A6', 'A7', 'A8',
      'e-tron', 'e-tron GT',
      'Q2', 'Q3', 'Q4 e-tron', 'Q5', 'Q7', 'Q8', 'Q8 e-tron',
      'RS3', 'RS4', 'RS5', 'RS6', 'RS7', 'RS Q3', 'RS Q8',
      'S3', 'S4', 'S5', 'S6', 'S7', 'S8', 'SQ5', 'SQ7', 'SQ8',
      'TT', 'TT RS',
    ],

    // ── B ──
    'BAIC': [
      'BJ20', 'BJ30', 'BJ40', 'BJ60', 'D20',
      'EU5', 'Senova X25', 'Senova X35', 'Senova X55', 'X7',
    ],
    'Bajaj': ['Boxer', 'Discover', 'Platina', 'Pulsar', 'Qute'],
    'Bentley': ['Bentayga', 'Continental GT', 'Flying Spur'],
    'BMW': [
      '1 Series', '2 Series', '3 Series', '4 Series', '5 Series',
      '6 Series', '7 Series', '8 Series',
      'i3', 'i4', 'i5', 'i7', 'iX', 'iX1', 'iX3',
      'M2', 'M3', 'M4', 'M5', 'M8',
      'X1', 'X2', 'X3', 'X4', 'X5', 'X6', 'X7', 'XM',
      'Z4',
    ],
    'Brilliance': ['H230', 'H330', 'H530', 'V3', 'V5', 'V6', 'V7'],
    'Bugatti': ['Chiron', 'Mistral', 'Tourbillon'],
    'BYD': [
      'Atto 3', 'Dolphin', 'Dolphin Mini', 'e2', 'e6', 'F3',
      'Han', 'Qin Plus', 'Seal', 'Seal U',
      'Song Plus', 'Tang', 'Yuan Plus',
    ],

    // ── C ──
    'Cadillac': ['CT4', 'CT5', 'Escalade', 'Lyriq', 'XT4', 'XT5', 'XT6'],
    'Changan': [
      'Alsvin', 'CS15', 'CS35', 'CS55', 'CS75', 'CS75 Plus', 'CS85', 'CS95',
      'Eado', 'Hunter', 'Lamore',
      'Oshan X5', 'Oshan X7',
      'Uni-K', 'Uni-T', 'Uni-V',
    ],
    'Changhe': ['A6', 'M50', 'M70', 'Q25', 'Q35'],
    'Chery': [
      'Arrizo 5', 'Arrizo 6', 'Arrizo 8',
      'eQ1', 'eQ5',
      'Omoda 5', 'Omoda 7',
      'QQ', 'QQ Ice Cream',
      'Tiggo 2', 'Tiggo 2 Pro', 'Tiggo 4', 'Tiggo 4 Pro',
      'Tiggo 5X', 'Tiggo 7', 'Tiggo 7 Pro',
      'Tiggo 8', 'Tiggo 8 Pro', 'Tiggo 9',
    ],
    'Chevrolet': [
      'Aveo', 'Blazer', 'Bolt', 'Camaro', 'Captiva', 'Colorado',
      'Corvette', 'Cruze', 'Equinox', 'Groove',
      'Malibu', 'Onix', 'Orlando',
      'Silverado', 'Spark', 'Suburban',
      'Tahoe', 'Tracker', 'Trailblazer', 'Traverse', 'Trax',
    ],
    'Chrysler': ['300', 'Pacifica', 'Voyager'],
    'Citroën': [
      'Berlingo', 'C-Elysée', 'C1', 'C3', 'C3 Aircross', 'C4', 'C4 X',
      'C5 Aircross', 'C5 X', 'Jumpy', 'SpaceTourer',
    ],

    // ── D ──
    'Dacia': ['Duster', 'Jogger', 'Logan', 'Sandero', 'Spring'],
    'Daewoo': ['Kalos', 'Lacetti', 'Matiz', 'Nubira', 'Winstorm'],
    'Daihatsu': ['Ayla', 'Gran Max', 'Rocky', 'Sigra', 'Terios', 'Xenia'],
    'Deepal': ['L07', 'S05', 'S07'],
    'DFSK': ['C31', 'C35', 'Glory 560', 'Glory 580', 'Glory i-Auto', 'K01', 'K05', 'Mini Bus'],
    'Dodge': [
      'Challenger', 'Charger', 'Durango', 'Hornet',
      'Journey', 'Ram 1500', 'Ram 2500',
    ],
    'DongFeng': [
      '007', '580', 'AX4', 'AX7', 'Box', 'E70', 'Fengon 500',
      'Glory 560', 'Joyear X5', 'Rich 6', 'S50',
    ],

    // ── F ──
    'FAW': ['Bestune B70', 'Bestune T33', 'Bestune T55', 'Bestune T77', 'Bestune T99', 'N5', 'Sirius S80', 'V80'],
    'Ferrari': ['296', '488', '812', 'F8', 'Portofino', 'Purosangue', 'Roma', 'SF90'],
    'Fiat': [
      '500', '500e', '500L', '500X',
      'Argo', 'Cronos', 'Doblo', 'Ducato',
      'Linea', 'Mobi', 'Panda', 'Punto', 'Strada', 'Tipo', 'Toro',
    ],
    'Ford': [
      'Bantam', 'Bronco', 'Bronco Sport',
      'EcoSport', 'Edge', 'Escape', 'Everest', 'Expedition', 'Explorer',
      'F-150', 'F-250', 'Figo', 'Fiesta', 'Focus', 'Freestyle',
      'Kuga', 'Maverick', 'Mustang', 'Mustang Mach-E',
      'Puma', 'Ranger', 'Ranger Raptor', 'Territory', 'Transit',
    ],
    'Foton': [
      'Auman', 'Gratour', 'Sauvana', 'Savanna', 'Toplander',
      'Tunland', 'View',
    ],

    // ── G ──
    'GAC': [
      'Aion S', 'Aion V', 'Aion Y',
      'Emkoo', 'Empow', 'GN6', 'GN8',
      'GS3', 'GS4', 'GS5', 'GS8', 'M6', 'M8',
    ],
    'Geely': [
      'Azkarra', 'Coolray', 'Emgrand', 'Geometry C',
      'Monjaro', 'Okavango', 'Starray', 'Tugella',
    ],
    'Genesis': [
      'Electrified G80', 'Electrified GV70',
      'G70', 'G80', 'G90',
      'GV60', 'GV70', 'GV80',
    ],
    'GMC': ['Acadia', 'Canyon', 'Hummer EV', 'Sierra', 'Terrain', 'Yukon'],
    'Great Wall': [
      'Haval H6', 'Haval Jolion', 'Ora',
      'Poer', 'Tank 300', 'Tank 500', 'Wingle',
    ],

    // ── H ──
    'Haval': [
      'Big Dog', 'Dargo', 'H1', 'H2', 'H4', 'H6', 'H6 PHEV', 'H9',
      'Jolion', 'Jolion S', 'Xiaolong MAX',
    ],
    'Higer': ['KLQ6109', 'KLQ6129', 'V91', 'V92'],
    'Honda': [
      'Accord', 'Amaze', 'BR-V', 'Brio', 'City',
      'Civic', 'CR-V', 'CR-Z',
      'Elevate', 'Fit', 'HR-V', 'Jazz', 'Mobilio', 'Odyssey',
      'Passport', 'Pilot', 'Prologue', 'Ridgeline', 'WR-V', 'ZR-V',
    ],
    'Hongqi': ['E-HS9', 'H5', 'H9', 'HS5', 'HS7'],
    'Hyundai': [
      'Accent', 'Aura', 'Bayon', 'Casper', 'Creta',
      'Elantra', 'Grand i10', 'i10', 'i20', 'i30',
      'Ioniq 5', 'Ioniq 6', 'Kona', 'Kona Electric', 'Nexo',
      'Palisade', 'Santa Cruz', 'Santa Fe', 'Sonata',
      'Staria', 'Stargazer', 'Tucson', 'Venue', 'Verna',
    ],

    // ── I ──
    'Infiniti': ['Q50', 'Q60', 'QX50', 'QX55', 'QX60', 'QX80'],
    'Innoson': [
      'Capa', 'Caris', 'Carrier', 'Fox',
      'G5', 'G6', 'G12', 'G40', 'G80',
      'IVM Connect', 'Umu',
    ],
    'Isuzu': [
      'D-Max', 'FRR', 'FTR', 'FVR', 'Giga',
      'MU-X', 'N-Series', 'NLR', 'NMR', 'NPR',
    ],

    // ── J ──
    'JAC': [
      'iEV7S', 'iEVS4', 'J4', 'J7', 'JS4',
      'S2', 'S3', 'S4', 'S7', 'T6', 'T8',
    ],
    'Jaecoo': ['J5', 'J7', 'J8'],
    'Jaguar': ['E-Pace', 'F-Pace', 'F-Type', 'I-Pace', 'XE', 'XF'],
    'Jeep': [
      'Avenger', 'Cherokee', 'Commander', 'Compass', 'Gladiator',
      'Grand Cherokee', 'Grand Wagoneer',
      'Renegade', 'Wagoneer', 'Wrangler',
    ],
    'Jetour': ['Dashing', 'T2', 'X70', 'X70 Plus', 'X90', 'X95'],
    'JMC': ['Boarding', 'Grand Tiger', 'Vigus', 'Yuhu'],

    // ── K ──
    'Kantanka': ['Mensah', 'Nkunimdie', 'Onantefo', 'Otumfuo'],
    'Kia': [
      'Carens', 'Carnival', 'Ceed', 'EV6', 'EV9',
      'Forte', 'K3', 'K5',
      'Niro', 'Pegas', 'Picanto', 'Rio',
      'Seltos', 'Sonet', 'Sorento', 'Soul',
      'Sportage', 'Stinger', 'Stonic', 'Telluride',
    ],
    'King Long': ['Kingo', 'Mini Van', 'Placer', 'Wide Body'],

    // ── L ──
    'Lada': ['Granta', 'Niva', 'Niva Legend', 'Vesta', 'XRAY'],
    'Lamborghini': ['Huracán', 'Revuelto', 'Urus'],
    'Land Rover': [
      'Defender', 'Discovery', 'Discovery Sport',
      'Range Rover', 'Range Rover Evoque',
      'Range Rover Sport', 'Range Rover Velar',
    ],
    'LDV': ['D90', 'Deliver 9', 'eDeliver 9', 'G10', 'T60', 'V80'],
    'Leapmotor': ['C10', 'C11', 'C16', 'S01', 'T03'],
    'Lexus': [
      'ES', 'GX', 'IS', 'LC', 'LS', 'LX',
      'NX', 'RC', 'RX', 'RZ', 'TX', 'UX',
    ],
    'Lincoln': ['Aviator', 'Corsair', 'Navigator'],
    'Lotus': ['Eletre', 'Emeya', 'Emira'],

    // ── M ──
    'Mahindra': [
      'Bolero', 'KUV100', 'Marazzo', 'Pik-Up',
      'Scorpio', 'Scorpio N', 'Thar',
      'XUV300', 'XUV400', 'XUV700',
    ],
    'Maserati': [
      'Ghibli', 'GranTurismo', 'Grecale',
      'Levante', 'MC20', 'Quattroporte',
    ],
    'Mazda': [
      '2', '3', '6', 'CX-3', 'CX-30', 'CX-5',
      'CX-50', 'CX-60', 'CX-8', 'CX-9', 'CX-90',
      'Demio', 'MX-5', 'MX-30',
    ],
    'McLaren': ['720S', '750S', 'Artura', 'GT'],
    'Mercedes-Benz': [
      'A-Class', 'AMG GT', 'B-Class', 'C-Class', 'CLA', 'CLE', 'CLS',
      'E-Class', 'EQA', 'EQB', 'EQC', 'EQE', 'EQS',
      'G-Class', 'GLA', 'GLB', 'GLC', 'GLE', 'GLS',
      'Maybach', 'S-Class', 'SL', 'Sprinter', 'V-Class', 'Vito',
      'X-Class',
    ],
    'MG': [
      '3', '4', '5', 'Cyberster', 'Gloster', 'Hector',
      'HS', 'MG4', 'MG5 EV', 'RX5', 'ZS', 'ZS EV',
    ],
    'Mini': [
      'Clubman', 'Convertible', 'Cooper', 'Cooper SE',
      'Countryman', 'Paceman',
    ],
    'Mitsubishi': [
      'ASX', 'Attrage', 'Eclipse Cross', 'L200', 'Mirage',
      'Montero', 'Outlander', 'Pajero', 'Pajero Sport',
      'Triton', 'Xforce', 'Xpander', 'Xpander Cross',
    ],

    // ── N ──
    'Nissan': [
      '370Z', 'Almera', 'Altima', 'Ariya',
      'Frontier', 'GT-R', 'Juke', 'Kicks',
      'Leaf', 'Livina', 'Magnite', 'March', 'Maxima', 'Micra', 'Murano',
      'Navara', 'Note', 'NP200', 'NP300',
      'Pathfinder', 'Patrol', 'Qashqai', 'Rogue',
      'Sentra', 'Sunny', 'Sylphy', 'Terra',
      'Titan', 'Versa', 'X-Trail', 'Z',
    ],
    'Nord': ['A5 Luxury', 'A7', 'A9', 'Demir', 'Flit', 'Max', 'Tank', 'Tripper', 'Tusk', 'Yarn'],

    // ── O ──
    'Opel': [
      'Astra', 'Combo', 'Corsa', 'Crossland',
      'Grandland', 'Mokka', 'Vivaro', 'Zafira',
    ],

    // ── P ──
    'Perodua': ['Alza', 'Ativa', 'Axia', 'Bezza', 'Myvi'],
    'Peugeot': [
      '2008', '208', '3008', '301', '308', '408', '5008', '508',
      'Boxer', 'Expert', 'Landtrek', 'Partner', 'Rifter',
    ],
    'Polestar': ['1', '2', '3', '4'],
    'Porsche': ['718', '911', 'Cayenne', 'Macan', 'Panamera', 'Taycan'],
    'Proton': ['Iriz', 'Persona', 'Saga', 'X50', 'X70', 'X90'],

    // ── R ──
    'RAM': ['1500', '2500', '3500', 'ProMaster'],
    'Renault': [
      'Arkana', 'Captur', 'Clio', 'Duster', 'Express',
      'Kadjar', 'Kangoo', 'Koleos', 'Kwid',
      'Logan', 'Master', 'Megane', 'Megane E-Tech',
      'Sandero', 'Scenic', 'Stepway', 'Symbol', 'Triber', 'Zoe',
    ],
    'Rivian': ['R1S', 'R1T', 'R2'],
    'Rolls-Royce': [
      'Cullinan', 'Dawn', 'Ghost',
      'Phantom', 'Spectre', 'Wraith',
    ],

    // ── S ──
    'Saipa': ['Quick', 'Saina', 'Shahin', 'Tiba'],
    'SEAT': ['Arona', 'Ateca', 'Ibiza', 'Leon', 'Tarraco'],
    'SinoTruk': ['Howo A7', 'Howo T5G', 'Howo T7H', 'Sitrak C7H', 'Sitrak G7'],
    'Škoda': [
      'Enyaq', 'Fabia', 'Kamiq', 'Karoq', 'Kodiaq',
      'Octavia', 'Rapid', 'Scala', 'Slavia', 'Superb',
    ],
    'Smart': ['#1', '#3', 'EQ ForTwo'],
    'SsangYong': ['Korando', 'Musso', 'Rexton', 'Tivoli', 'Torres'],
    'Stallion': ['Centaur', 'Kona Electric', 'NP300 Hardbody', 'Stallion Jeep'],
    'Subaru': [
      'BRZ', 'Crosstrek', 'Forester', 'Impreza',
      'Legacy', 'Outback', 'Solterra', 'WRX', 'XV',
    ],
    'Suzuki': [
      'Alto', 'APV', 'Baleno', 'Brezza', 'Carry', 'Celerio', 'Ciaz',
      'Dzire', 'Ertiga', 'Fronx', 'Grand Vitara', 'Ignis',
      'Jimny', 'S-Cross', 'S-Presso', 'Swift', 'Vitara', 'XL6', 'XL7',
    ],

    // ── T ──
    'Tata': [
      'Altroz', 'Curvv', 'Harrier', 'Nano',
      'Nexon', 'Punch', 'Safari', 'Tiago', 'Tigor',
    ],
    'Tesla': ['Cybertruck', 'Model 3', 'Model S', 'Model X', 'Model Y', 'Semi'],
    'Toyota': [
      '4Runner', 'Agya', 'Alphard', 'Aqua', 'Avanza', 'Avalon',
      'bZ4X', 'Calya', 'Camry', 'C-HR', 'Corolla', 'Corolla Cross', 'Crown',
      'Etios', 'Fielder', 'FJ Cruiser', 'Fortuner',
      'GR86', 'GR Corolla', 'GR Supra', 'GR Yaris',
      'Harrier', 'Hiace', 'Highlander', 'Hilux',
      'Innova', 'Innova Hycross',
      'Land Cruiser', 'Land Cruiser 300', 'Noah',
      'Prado', 'Prius', 'Probox', 'RAV4', 'Raize', 'Rush', 'Rumion',
      'Sequoia', 'Sienta', 'Starlet', 'Tacoma', 'Tundra', 'Urban Cruiser',
      'Veloz', 'Venza', 'Vios', 'Voxy', 'Wish', 'Yaris', 'Yaris Cross',
    ],

    // ── V ──
    'Volkswagen': [
      'Amarok', 'Arteon', 'Atlas', 'Caddy',
      'Golf', 'Gol', 'ID.3', 'ID.4', 'ID.5', 'ID.Buzz',
      'Jetta', 'Nivus', 'Passat', 'Polo', 'Polo Vivo', 'Saveiro',
      'T-Cross', 'T-Roc', 'Taigo', 'Taos',
      'Tiguan', 'Touareg', 'Transporter', 'Up!', 'Virtus',
    ],
    'Volvo': [
      'C40', 'EX30', 'EX90',
      'S60', 'S90', 'V60', 'V90',
      'XC40', 'XC60', 'XC90',
    ],

    // ── W ──
    'Wallyscar': ['Iris'],
    'Wuling': ['Air EV', 'Almaz', 'Confero', 'Cortez', 'Formo'],

    // ── Y ──
    'Yutong': ['E10', 'E12', 'Master', 'TC12', 'ZK6122', 'ZK6128'],

    // ── Z ──
    'Zeekr': ['001', '007', '009', 'X'],
    'ZOTYE': ['T300', 'T500', 'T600', 'T700', 'T800'],
    'ZS (Zotye)': ['C11', 'SR7', 'SR9', 'T300', 'T600'],
  };

  /// Year range for vehicle listings
  static List<String> get years {
    final currentYear = DateTime.now().year;
    return List.generate(
      currentYear - 1969, // From 1970 to current year + 1
      (i) => (currentYear + 1 - i).toString(),
    );
  }
}
