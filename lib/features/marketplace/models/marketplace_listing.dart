import 'package:cloud_firestore/cloud_firestore.dart';

// ─── Category Constants ───
class MarketplaceCategory {
  // Products
  static const String vehicles = 'vehicles';
  static const String motorcycles = 'motorcycles';
  static const String carParts = 'car_parts';
  static const String realEstate = 'real_estate';
  static const String electronics = 'electronics';
  static const String fashion = 'fashion';
  static const String foodGrocery = 'food_grocery';
  static const String homeGarden = 'home_garden';
  static const String health = 'health';
  static const String sports = 'sports';
  static const String booksMedia = 'books_media';
  static const String otherProducts = 'other_products';

  // Services
  static const String professional = 'professional';
  static const String techDigital = 'tech_digital';
  static const String education = 'education';
  static const String homeServices = 'home_services';
  static const String transport = 'transport';
  static const String eventsCatering = 'events_catering';
  static const String financial = 'financial';
  static const String wellness = 'wellness';
  static const String travel = 'travel';
  static const String otherServices = 'other_services';

  // Jobs
  static const String jobTechnology = 'job_technology';
  static const String jobHealthcare = 'job_healthcare';
  static const String jobFinance = 'job_finance';
  static const String jobEngineering = 'job_engineering';
  static const String jobEducation = 'job_education';
  static const String jobMarketing = 'job_marketing';
  static const String jobSales = 'job_sales';
  static const String jobCustomerService = 'job_customer_service';
  static const String jobAdminHR = 'job_admin_hr';
  static const String jobConstruction = 'job_construction';
  static const String jobTransportLogistics = 'job_transport_logistics';
  static const String jobHospitality = 'job_hospitality';
  static const String jobRetail = 'job_retail';
  static const String jobCreativeMedia = 'job_creative_media';
  static const String jobOther = 'job_other';

  static const List<String> productCategories = [
    vehicles,
    motorcycles,
    carParts,
    realEstate,
    electronics,
    fashion,
    foodGrocery,
    homeGarden,
    health,
    sports,
    booksMedia,
    otherProducts,
  ];

  static const List<String> serviceCategories = [
    professional,
    techDigital,
    education,
    homeServices,
    transport,
    eventsCatering,
    financial,
    wellness,
    travel,
    otherServices,
  ];

  static const List<String> jobCategories = [
    jobTechnology,
    jobHealthcare,
    jobFinance,
    jobEngineering,
    jobEducation,
    jobMarketing,
    jobSales,
    jobCustomerService,
    jobAdminHR,
    jobConstruction,
    jobTransportLogistics,
    jobHospitality,
    jobRetail,
    jobCreativeMedia,
    jobOther,
  ];

  static String displayName(String id) {
    switch (id) {
      case vehicles:
        return 'Cars';
      case motorcycles:
        return 'Motorcycles';
      case carParts:
        return 'Car Parts';
      case realEstate:
        return 'Real Estate';
      case electronics:
        return 'Electronics';
      case fashion:
        return 'Fashion & Beauty';
      case foodGrocery:
        return 'Food & Grocery';
      case homeGarden:
        return 'Home & Garden';
      case health:
        return 'Health & Wellness';
      case sports:
        return 'Sports & Outdoors';
      case booksMedia:
        return 'Books & Media';
      case otherProducts:
        return 'Other Products';
      case professional:
        return 'Professional';
      case techDigital:
        return 'Tech & Digital';
      case education:
        return 'Education & Tutoring';
      case homeServices:
        return 'Home Services';
      case transport:
        return 'Transport & Logistics';
      case eventsCatering:
        return 'Events & Catering';
      case financial:
        return 'Financial Services';
      case wellness:
        return 'Wellness & Care';
      case travel:
        return 'Travel & Tourism';
      case otherServices:
        return 'Other Services';
      case jobTechnology:
        return 'Technology';
      case jobHealthcare:
        return 'Healthcare';
      case jobFinance:
        return 'Finance & Accounting';
      case jobEngineering:
        return 'Engineering';
      case jobEducation:
        return 'Education & Training';
      case jobMarketing:
        return 'Marketing & Comms';
      case jobSales:
        return 'Sales & Business Dev';
      case jobCustomerService:
        return 'Customer Service';
      case jobAdminHR:
        return 'Admin & HR';
      case jobConstruction:
        return 'Construction & Trades';
      case jobTransportLogistics:
        return 'Transport & Logistics';
      case jobHospitality:
        return 'Hospitality & Food';
      case jobRetail:
        return 'Retail & Warehouse';
      case jobCreativeMedia:
        return 'Creative & Media';
      case jobOther:
        return 'Other Jobs';
      default:
        return id;
    }
  }

  static String emoji(String id) {
    switch (id) {
      case vehicles:
        return '🚗';
      case motorcycles:
        return '🏍️';
      case carParts:
        return '🔧';
      case realEstate:
        return '🏠';
      case electronics:
        return '📱';
      case fashion:
        return '👕';
      case foodGrocery:
        return '🥘';
      case homeGarden:
        return '🏡';
      case health:
        return '💊';
      case sports:
        return '⚽';
      case booksMedia:
        return '📚';
      case otherProducts:
        return '📦';
      case professional:
        return '💼';
      case techDigital:
        return '💻';
      case education:
        return '🎓';
      case homeServices:
        return '🔧';
      case transport:
        return '🚐';
      case eventsCatering:
        return '🎉';
      case financial:
        return '💰';
      case wellness:
        return '🧘';
      case travel:
        return '✈️';
      case otherServices:
        return '🛠️';
      case jobTechnology:
        return '💻';
      case jobHealthcare:
        return '🏥';
      case jobFinance:
        return '📊';
      case jobEngineering:
        return '⚙️';
      case jobEducation:
        return '📖';
      case jobMarketing:
        return '📣';
      case jobSales:
        return '🤝';
      case jobCustomerService:
        return '🎧';
      case jobAdminHR:
        return '🗂️';
      case jobConstruction:
        return '🏗️';
      case jobTransportLogistics:
        return '🚚';
      case jobHospitality:
        return '🍽️';
      case jobRetail:
        return '🛒';
      case jobCreativeMedia:
        return '🎨';
      case jobOther:
        return '💼';
      default:
        return '📦';
    }
  }

  /// Subcategories per category
  static List<String> subcategories(String categoryId) {
    switch (categoryId) {
      case vehicles:
        return ['Sedans', 'SUVs', 'Trucks', 'Vans', 'Buses', 'Other'];
      case motorcycles:
        return [
          'Sport',
          'Naked / Street',
          'Cruiser',
          'Adventure',
          'Touring',
          'Scooter',
          'Commuter',
          'Off-Road',
          'Tricycle / Tuk-Tuk',
          'Trike',
          'Electric',
          'Other',
        ];
      case carParts:
        return [
          'Engine & Drivetrain',
          'Transmission',
          'Body & Exterior',
          'Electrical & Lighting',
          'Suspension & Steering',
          'Brakes',
          'Interior',
          'Wheels & Tires',
          'A/C & Heating',
          'Exhaust',
          'Other Parts',
        ];
      case realEstate:
        return [
          'Houses',
          'Apartments',
          'Land',
          'Commercial Property',
          'Rental',
        ];
      case electronics:
        return [
          'Phones & Tablets',
          'Laptops & Computers',
          'TVs & Audio',
          'Cameras',
          'Accessories',
        ];
      case fashion:
        return [
          'Clothing',
          'Shoes',
          'Jewelry & Watches',
          'African Wear',
          'Beauty Products',
        ];
      case foodGrocery:
        return [
          'African Foods',
          'Spices & Seasonings',
          'Beverages',
          'Catering Packages',
          'Other',
        ];
      case homeGarden:
        return ['Furniture', 'Appliances', 'Kitchen', 'Decor', 'Tools'];
      case health:
        return [
          'Supplements',
          'Equipment',
          'Natural Remedies',
          'Personal Care',
        ];
      case sports:
        return ['Gym Equipment', 'Sports Gear', 'Outdoor', 'Activewear'];
      case booksMedia:
        return ['Books', 'Music', 'Movies', 'Art & Crafts'];
      case professional:
        return [
          'Legal',
          'Accounting & Tax',
          'Consulting',
          'Translation & Interpretation',
          'Immigration',
        ];
      case techDigital:
        return [
          'Web Development',
          'App Development',
          'IT Support',
          'Graphic Design',
          'Social Media',
        ];
      case education:
        return [
          'Tutoring',
          'Language Lessons',
          'Test Prep',
          'Mentoring',
          'Courses',
        ];
      case homeServices:
        return [
          'Cleaning',
          'Plumbing',
          'Electrical',
          'Moving & Hauling',
          'Repairs',
        ];
      case transport:
        return [
          'Shipping to Africa',
          'Local Delivery',
          'Moving Services',
          'Courier',
        ];
      case eventsCatering:
        return [
          'Event Planning',
          'Catering',
          'DJ & Music',
          'Photography',
          'Venue Rental',
        ];
      case financial:
        return [
          'Tax Filing',
          'Bookkeeping',
          'Investment Advisory',
          'Insurance',
        ];
      case wellness:
        return [
          'Hair Braiding',
          'Barbering',
          'Personal Training',
          'Childcare',
          'Massage',
        ];
      case travel:
        return [
          'Travel Packages',
          'Visa Assistance',
          'Tour Guides',
          'Hotel Booking',
        ];
      case jobTechnology:
        return [
          'Software Engineering',
          'Data Science',
          'Cybersecurity',
          'DevOps',
          'IT Support',
          'Product Management',
        ];
      case jobHealthcare:
        return [
          'Nursing',
          'Doctors',
          'Pharmacists',
          'Lab Technicians',
          'Home Health Aides',
          'Dentistry',
        ];
      case jobFinance:
        return [
          'Accounting',
          'Financial Analysis',
          'Banking',
          'Insurance',
          'Tax Advisory',
          'Auditing',
        ];
      case jobEngineering:
        return [
          'Civil',
          'Mechanical',
          'Electrical',
          'Chemical',
          'Environmental',
        ];
      case jobEducation:
        return [
          'Teaching',
          'Training',
          'Curriculum Design',
          'Tutoring',
          'Administration',
        ];
      case jobMarketing:
        return [
          'Digital Marketing',
          'Content Strategy',
          'PR & Comms',
          'SEO/SEM',
          'Brand Management',
        ];
      case jobSales:
        return [
          'Account Executive',
          'Business Development',
          'Retail Sales',
          'Inside Sales',
          'Partnerships',
        ];
      case jobCustomerService:
        return [
          'Call Center',
          'Help Desk',
          'Client Relations',
          'Technical Support',
        ];
      case jobAdminHR:
        return [
          'Office Admin',
          'Recruiting',
          'Payroll',
          'Executive Assistant',
          'HR Management',
        ];
      case jobConstruction:
        return [
          'General Labor',
          'Electricians',
          'Plumbing',
          'Carpentry',
          'Project Management',
        ];
      case jobTransportLogistics:
        return [
          'Driving',
          'Warehouse',
          'Supply Chain',
          'Dispatching',
          'Fleet Management',
        ];
      case jobHospitality:
        return ['Restaurant', 'Hotel', 'Catering', 'Event Staff', 'Barista'];
      case jobRetail:
        return [
          'Cashier',
          'Store Management',
          'Inventory',
          'Visual Merchandising',
        ];
      case jobCreativeMedia:
        return [
          'Graphic Design',
          'Video Production',
          'Photography',
          'Copywriting',
          'Social Media',
        ];
      case jobOther:
        return ['Internship', 'Volunteer', 'Freelance', 'Contract', 'Other'];
      default:
        return ['General'];
    }
  }
}

// ─── Listing Type ───
class ListingType {
  static const String product = 'product';
  static const String job = 'job';
  static const String service = 'service';
}

// ─── Listing Scope ───
class ListingScope {
  static const String local = 'local';
  static const String international = 'international';
}

// ─── Item Condition ───
class ItemCondition {
  static const String brandNew = 'new';
  static const String likeNew = 'like_new';
  static const String usedGood = 'used_good';
  static const String usedFair = 'used_fair';

  static String displayName(String id) {
    switch (id) {
      case brandNew:
        return 'New';
      case likeNew:
        return 'Like New';
      case usedGood:
        return 'Used - Good';
      case usedFair:
        return 'Used - Fair';
      default:
        return id;
    }
  }
}

// ─── Listing Status ───
class ListingStatus {
  static const String active = 'active';
  static const String sold = 'sold';
  static const String paused = 'paused';
  static const String expired = 'expired';
  static const String flagged = 'flagged';
}

// ─── Contact Method ───
class ContactMethod {
  static const String chat = 'chat';
  static const String phone = 'phone';
  static const String whatsapp = 'whatsapp';
  static const String email = 'email';
}

// ─── Location Model ───
class ListingLocation {
  final String? city;
  final String? country;
  final String? countryCode;
  final String? formattedAddress;

  ListingLocation({
    this.city,
    this.country,
    this.countryCode,
    this.formattedAddress,
  });

  Map<String, dynamic> toMap() => {
    'city': city,
    'country': country,
    'countryCode': countryCode,
    'formattedAddress': formattedAddress,
  };

  factory ListingLocation.fromMap(Map<String, dynamic> map) => ListingLocation(
    city: map['city'] as String?,
    country: map['country'] as String?,
    countryCode: map['countryCode'] as String?,
    formattedAddress: map['formattedAddress'] as String?,
  );
}

// ─── Main Listing Model ───
class MarketplaceListing {
  final String id;
  final String sellerId;
  final String sellerName;
  final String? sellerPhoto;
  final String? sellerCountryCode;
  final String? sellerCity;
  final String? orgId; // Organization that owns this listing
  final String? orgName;

  // Core
  final String title;
  final String description;
  final String category;
  final String? subcategory;
  final String listingType; // 'product' or 'service'
  final String scope; // 'local' or 'international'

  // Pricing
  final double priceAmount; // In $DIASPORA
  final bool priceNegotiable;

  // Product-specific
  final String? condition; // new, like_new, used_good, used_fair

  // Contextual detail maps — category-specific fields
  final Map<String, dynamic>? vehicleDetails;
  final Map<String, dynamic>? motorcycleDetails;
  final Map<String, dynamic>? carPartsDetails;
  final Map<String, dynamic>? realEstateDetails;
  final Map<String, dynamic>? electronicsDetails;
  final Map<String, dynamic>? serviceDetails;
  final Map<String, dynamic>? jobDetails;

  // Media
  final List<String> images;
  final List<String>? tags;

  // Location
  final ListingLocation? location;

  // Logistics
  final List<String>? deliveryOptions; // pickup, delivery, shipping, digital
  final String contactMethod; // chat, phone, whatsapp, email

  // State
  final String status;
  final int viewCount;
  final int savedCount;
  final int reportCount;

  // Timestamps
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? expiresAt;

  // Community visibility — which communities can see this listing
  final List<String>? communityIds;

  MarketplaceListing({
    required this.id,
    required this.sellerId,
    required this.sellerName,
    this.sellerPhoto,
    this.sellerCountryCode,
    this.sellerCity,
    this.orgId,
    this.orgName,
    required this.title,
    required this.description,
    required this.category,
    this.subcategory,
    required this.listingType,
    required this.scope,
    required this.priceAmount,
    this.priceNegotiable = false,
    this.condition,
    this.vehicleDetails,
    this.motorcycleDetails,
    this.carPartsDetails,
    this.realEstateDetails,
    this.electronicsDetails,
    this.serviceDetails,
    this.jobDetails,
    this.images = const [],
    this.tags,
    this.location,
    this.deliveryOptions,
    this.contactMethod = ContactMethod.chat,
    this.status = ListingStatus.active,
    this.viewCount = 0,
    this.savedCount = 0,
    this.reportCount = 0,
    this.createdAt,
    this.updatedAt,
    this.expiresAt,
    this.communityIds,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sellerId': sellerId,
      'sellerName': sellerName,
      'sellerPhoto': sellerPhoto,
      'sellerCountryCode': sellerCountryCode,
      'sellerCity': sellerCity,
      'orgId': orgId,
      'orgName': orgName,
      'title': title,
      'description': description,
      'category': category,
      'subcategory': subcategory,
      'listingType': listingType,
      'scope': scope,
      'priceAmount': priceAmount,
      'priceNegotiable': priceNegotiable,
      'condition': condition,
      'vehicleDetails': vehicleDetails,
      'motorcycleDetails': motorcycleDetails,
      'carPartsDetails': carPartsDetails,
      'realEstateDetails': realEstateDetails,
      'electronicsDetails': electronicsDetails,
      'serviceDetails': serviceDetails,
      'jobDetails': jobDetails,
      'images': images,
      'tags': tags,
      'location': location?.toMap(),
      'deliveryOptions': deliveryOptions,
      'contactMethod': contactMethod,
      'status': status,
      'viewCount': viewCount,
      'savedCount': savedCount,
      'reportCount': reportCount,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
      'communityIds': communityIds,
      // Searchable lowercase title for queries
      'titleLower': title.toLowerCase(),
    };
  }

  factory MarketplaceListing.fromMap(Map<String, dynamic> map, String docId) {
    return MarketplaceListing(
      id: docId,
      sellerId: map['sellerId'] as String? ?? '',
      sellerName: map['sellerName'] as String? ?? '',
      sellerPhoto: map['sellerPhoto'] as String?,
      sellerCountryCode: map['sellerCountryCode'] as String?,
      sellerCity: map['sellerCity'] as String?,
      orgId: map['orgId'] as String?,
      orgName: map['orgName'] as String?,
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      category: map['category'] as String? ?? '',
      subcategory: map['subcategory'] as String?,
      listingType: map['listingType'] as String? ?? ListingType.product,
      scope: map['scope'] as String? ?? ListingScope.local,
      priceAmount: (map['priceAmount'] as num?)?.toDouble() ?? 0,
      priceNegotiable: map['priceNegotiable'] as bool? ?? false,
      condition: map['condition'] as String?,
      vehicleDetails: map['vehicleDetails'] as Map<String, dynamic>?,
      motorcycleDetails: map['motorcycleDetails'] as Map<String, dynamic>?,
      carPartsDetails: map['carPartsDetails'] as Map<String, dynamic>?,
      realEstateDetails: map['realEstateDetails'] as Map<String, dynamic>?,
      electronicsDetails: map['electronicsDetails'] as Map<String, dynamic>?,
      serviceDetails: map['serviceDetails'] as Map<String, dynamic>?,
      jobDetails: map['jobDetails'] as Map<String, dynamic>?,
      images:
          (map['images'] as List<dynamic>?)?.map((e) => e as String).toList() ??
          [],
      tags: (map['tags'] as List<dynamic>?)?.map((e) => e as String).toList(),
      location: map['location'] != null
          ? ListingLocation.fromMap(map['location'] as Map<String, dynamic>)
          : null,
      deliveryOptions: (map['deliveryOptions'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      contactMethod: map['contactMethod'] as String? ?? ContactMethod.chat,
      status: map['status'] as String? ?? ListingStatus.active,
      viewCount: map['viewCount'] as int? ?? 0,
      savedCount: map['savedCount'] as int? ?? 0,
      reportCount: map['reportCount'] as int? ?? 0,
      createdAt: map['createdAt'] is Timestamp
          ? (map['createdAt'] as Timestamp).toDate()
          : null,
      updatedAt: map['updatedAt'] is Timestamp
          ? (map['updatedAt'] as Timestamp).toDate()
          : null,
      expiresAt: map['expiresAt'] is Timestamp
          ? (map['expiresAt'] as Timestamp).toDate()
          : null,
      communityIds: (map['communityIds'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
    );
  }

  MarketplaceListing copyWith({
    String? id,
    String? sellerId,
    String? sellerName,
    String? sellerPhoto,
    String? sellerCountryCode,
    String? sellerCity,
    String? orgId,
    String? orgName,
    String? title,
    String? description,
    String? category,
    String? subcategory,
    String? listingType,
    String? scope,
    double? priceAmount,
    bool? priceNegotiable,
    String? condition,
    Map<String, dynamic>? vehicleDetails,
    Map<String, dynamic>? motorcycleDetails,
    Map<String, dynamic>? carPartsDetails,
    Map<String, dynamic>? realEstateDetails,
    Map<String, dynamic>? electronicsDetails,
    Map<String, dynamic>? serviceDetails,
    Map<String, dynamic>? jobDetails,
    List<String>? images,
    List<String>? tags,
    ListingLocation? location,
    List<String>? deliveryOptions,
    String? contactMethod,
    String? status,
    int? viewCount,
    int? savedCount,
    int? reportCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? expiresAt,
    List<String>? communityIds,
  }) {
    return MarketplaceListing(
      id: id ?? this.id,
      sellerId: sellerId ?? this.sellerId,
      sellerName: sellerName ?? this.sellerName,
      sellerPhoto: sellerPhoto ?? this.sellerPhoto,
      sellerCountryCode: sellerCountryCode ?? this.sellerCountryCode,
      sellerCity: sellerCity ?? this.sellerCity,
      orgId: orgId ?? this.orgId,
      orgName: orgName ?? this.orgName,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      subcategory: subcategory ?? this.subcategory,
      listingType: listingType ?? this.listingType,
      scope: scope ?? this.scope,
      priceAmount: priceAmount ?? this.priceAmount,
      priceNegotiable: priceNegotiable ?? this.priceNegotiable,
      condition: condition ?? this.condition,
      vehicleDetails: vehicleDetails ?? this.vehicleDetails,
      motorcycleDetails: motorcycleDetails ?? this.motorcycleDetails,
      carPartsDetails: carPartsDetails ?? this.carPartsDetails,
      realEstateDetails: realEstateDetails ?? this.realEstateDetails,
      electronicsDetails: electronicsDetails ?? this.electronicsDetails,
      serviceDetails: serviceDetails ?? this.serviceDetails,
      jobDetails: jobDetails ?? this.jobDetails,
      images: images ?? this.images,
      tags: tags ?? this.tags,
      location: location ?? this.location,
      deliveryOptions: deliveryOptions ?? this.deliveryOptions,
      contactMethod: contactMethod ?? this.contactMethod,
      status: status ?? this.status,
      viewCount: viewCount ?? this.viewCount,
      savedCount: savedCount ?? this.savedCount,
      reportCount: reportCount ?? this.reportCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      communityIds: communityIds ?? this.communityIds,
    );
  }
}
