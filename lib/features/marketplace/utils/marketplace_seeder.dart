import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:diaspora_nearby/features/marketplace/models/marketplace_listing.dart';
import 'package:diaspora_nearby/features/shared/utils/mock_photos.dart';

/// Seed mock marketplace listings — one per category.
/// Call `MarketplaceSeeder.seed(sellerId, sellerName)` to populate Firestore.
class MarketplaceSeeder {
  static final _firestore = FirebaseFirestore.instance;

  static Future<void> seed(String sellerId, String sellerName) async {
    final listings = _buildMockListings(sellerId, sellerName);
    final batch = _firestore.batch();

    for (final listing in listings) {
      final docRef = _firestore.collection('marketplace_listings').doc();
      final data = listing.copyWith(id: docRef.id).toMap();
      batch.set(docRef, data);
    }

    await batch.commit();
    debugPrint('✅ Seeded ${listings.length} mock marketplace listings');
  }

  /// Delete all mock listings (those with tag "mock_seed")
  static Future<void> clearSeeded() async {
    final snapshot = await _firestore
        .collection('marketplace_listings')
        .where('tags', arrayContains: 'mock_seed')
        .get();

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
    debugPrint('🗑️ Cleared ${snapshot.docs.length} mock listings');
  }

  static List<MarketplaceListing> _buildMockListings(
    String sellerId,
    String sellerName,
  ) {
    final now = DateTime.now();

    return [
      // ─── PRODUCTS ──────────────────────────────────────────────────────

      // 1. Vehicles
      MarketplaceListing(
        id: '',
        sellerId: sellerId,
        sellerName: sellerName,
        sellerCity: 'Dar es Salaam',
        sellerCountryCode: 'TZ',
        title: '2021 Toyota Land Cruiser V8',
        description:
            'Pristine condition Land Cruiser V8 with leather interior, sunroof, and full service history. Perfect for city and off-road driving. Only 28,000 km.',
        category: MarketplaceCategory.vehicles,
        subcategory: 'Cars',
        listingType: ListingType.product,
        scope: ListingScope.local,
        priceAmount: 85000,
        priceNegotiable: true,
        condition: ItemCondition.likeNew,
        vehicleDetails: {
          'make': 'Toyota',
          'model': 'Land Cruiser V8',
          'year': '2021',
          'mileage': '28000',
          'transmission': 'Automatic',
          'fuelType': 'Diesel',
          'driveType': '4WD',
        },
        images: MockPhotos.vehiclePhotos,
        tags: ['mock_seed', 'toyota', 'suv'],
        deliveryOptions: ['pickup'],
        contactMethod: ContactMethod.whatsapp,
        createdAt: now.subtract(const Duration(hours: 2)),
        communityIds: [], // visible to all
      ),

      // 2. Real Estate
      MarketplaceListing(
        id: '',
        sellerId: sellerId,
        sellerName: sellerName,
        sellerCity: 'Nairobi',
        sellerCountryCode: 'KE',
        title: '3 Bedroom Apartment in Kilimani',
        description:
            'Modern 3-bedroom apartment with open-plan kitchen, master en-suite, 24/7 security, gym, and swimming pool access. Prime Kilimani location.',
        category: MarketplaceCategory.realEstate,
        subcategory: 'Apartments',
        listingType: ListingType.product,
        scope: ListingScope.local,
        priceAmount: 120000,
        priceNegotiable: true,
        condition: ItemCondition.brandNew,
        realEstateDetails: {
          'bedrooms': '3',
          'bathrooms': '2',
          'squareFootage': '1800',
          'listingPurpose': 'For Sale',
          'address': 'Kilimani, Nairobi, Kenya',
        },
        images: MockPhotos.realEstateMarketplacePhotos,
        tags: ['mock_seed', 'apartment', 'nairobi'],
        deliveryOptions: ['pickup'],
        contactMethod: ContactMethod.phone,
        createdAt: now.subtract(const Duration(hours: 5)),
        communityIds: [],
      ),

      // 3. Electronics
      MarketplaceListing(
        id: '',
        sellerId: sellerId,
        sellerName: sellerName,
        sellerCity: 'Lagos',
        sellerCountryCode: 'NG',
        title: 'iPhone 15 Pro Max 256GB',
        description:
            'Brand new sealed iPhone 15 Pro Max, Natural Titanium. 256GB storage. Apple warranty intact. Comes with original accessories.',
        category: MarketplaceCategory.electronics,
        subcategory: 'Phones & Tablets',
        listingType: ListingType.product,
        scope: ListingScope.international,
        priceAmount: 4500,
        priceNegotiable: false,
        condition: ItemCondition.brandNew,
        electronicsDetails: {
          'brand': 'Apple',
          'model': 'iPhone 15 Pro Max',
          'storage': '256GB',
        },
        images: MockPhotos.electronicsPhotos,
        tags: ['mock_seed', 'iphone', 'apple'],
        deliveryOptions: ['shipping', 'pickup'],
        contactMethod: ContactMethod.chat,
        createdAt: now.subtract(const Duration(hours: 8)),
        communityIds: [],
      ),

      // 4. Fashion
      MarketplaceListing(
        id: '',
        sellerId: sellerId,
        sellerName: sellerName,
        sellerCity: 'Accra',
        sellerCountryCode: 'GH',
        title: 'Handmade Kente Cloth Collection',
        description:
            'Authentic handwoven Kente cloth from Bonwire, Ashanti Region. Perfect for weddings, ceremonies, and cultural events. Available in multiple patterns.',
        category: MarketplaceCategory.fashion,
        subcategory: 'African Wear',
        listingType: ListingType.product,
        scope: ListingScope.international,
        priceAmount: 1200,
        priceNegotiable: true,
        condition: ItemCondition.brandNew,
        images: MockPhotos.fashionPhotos,
        tags: ['mock_seed', 'kente', 'african', 'handmade'],
        deliveryOptions: ['shipping', 'pickup'],
        contactMethod: ContactMethod.whatsapp,
        createdAt: now.subtract(const Duration(hours: 12)),
        communityIds: [],
      ),

      // 5. Food & Grocery
      MarketplaceListing(
        id: '',
        sellerId: sellerId,
        sellerName: sellerName,
        sellerCity: 'London',
        sellerCountryCode: 'GB',
        title: 'Authentic Nigerian Spice Bundle',
        description:
            'Premium selection of Nigerian spices and seasonings — Cameroon pepper, crayfish, ogiri, locust beans, dawadawa, and suya spice. Fresh and authentic.',
        category: MarketplaceCategory.foodGrocery,
        subcategory: 'Spices & Seasonings',
        listingType: ListingType.product,
        scope: ListingScope.international,
        priceAmount: 350,
        priceNegotiable: false,
        condition: ItemCondition.brandNew,
        images: MockPhotos.foodPhotos,
        tags: ['mock_seed', 'spices', 'nigerian', 'food'],
        deliveryOptions: ['shipping', 'delivery'],
        contactMethod: ContactMethod.chat,
        createdAt: now.subtract(const Duration(hours: 18)),
        communityIds: [],
      ),

      // 6. Home & Garden
      MarketplaceListing(
        id: '',
        sellerId: sellerId,
        sellerName: sellerName,
        sellerCity: 'Johannesburg',
        sellerCountryCode: 'ZA',
        title: 'Handcrafted Teak Dining Set (6 seater)',
        description:
            'Beautiful solid teak wood dining table with 6 matching chairs. Hand-carved detailing. Perfect condition. Originally purchased for R45,000.',
        category: MarketplaceCategory.homeGarden,
        subcategory: 'Furniture',
        listingType: ListingType.product,
        scope: ListingScope.local,
        priceAmount: 5500,
        priceNegotiable: true,
        condition: ItemCondition.usedGood,
        images: MockPhotos.homeGardenPhotos,
        tags: ['mock_seed', 'furniture', 'dining'],
        deliveryOptions: ['pickup', 'delivery'],
        contactMethod: ContactMethod.phone,
        createdAt: now.subtract(const Duration(days: 1)),
        communityIds: [],
      ),

      // 7. Health
      MarketplaceListing(
        id: '',
        sellerId: sellerId,
        sellerName: sellerName,
        sellerCity: 'Addis Ababa',
        sellerCountryCode: 'ET',
        title: 'Organic Moringa Powder (1kg)',
        description:
            'Pure organic moringa leaf powder. Rich in vitamins, minerals, and antioxidants. Sourced directly from Ethiopian farms. Lab tested.',
        category: MarketplaceCategory.health,
        subcategory: 'Supplements',
        listingType: ListingType.product,
        scope: ListingScope.international,
        priceAmount: 180,
        priceNegotiable: false,
        condition: ItemCondition.brandNew,
        images: MockPhotos.healthPhotos,
        tags: ['mock_seed', 'moringa', 'organic', 'health'],
        deliveryOptions: ['shipping'],
        contactMethod: ContactMethod.chat,
        createdAt: now.subtract(const Duration(days: 1, hours: 6)),
        communityIds: [],
      ),

      // 8. Sports
      MarketplaceListing(
        id: '',
        sellerId: sellerId,
        sellerName: sellerName,
        sellerCity: 'Cairo',
        sellerCountryCode: 'EG',
        title: 'Full Home Gym Setup',
        description:
            'Complete home gym: Olympic barbell, 150kg plates, adjustable bench, squat rack, dumbbells (5-30kg), and rubber flooring. Barely used.',
        category: MarketplaceCategory.sports,
        subcategory: 'Gym Equipment',
        listingType: ListingType.product,
        scope: ListingScope.local,
        priceAmount: 8500,
        priceNegotiable: true,
        condition: ItemCondition.likeNew,
        images: MockPhotos.sportsPhotos,
        tags: ['mock_seed', 'gym', 'fitness', 'workout'],
        deliveryOptions: ['pickup'],
        contactMethod: ContactMethod.phone,
        createdAt: now.subtract(const Duration(days: 2)),
        communityIds: [],
      ),

      // 9. Books & Media
      MarketplaceListing(
        id: '',
        sellerId: sellerId,
        sellerName: sellerName,
        sellerCity: 'Kigali',
        sellerCountryCode: 'RW',
        title: 'African Literature Collection (25 books)',
        description:
            'Curated collection of 25 essential African literature classics including Chinua Achebe, Ngũgĩ wa Thiong\'o, Chimamanda Adichie, and more. Excellent condition.',
        category: MarketplaceCategory.booksMedia,
        subcategory: 'Books',
        listingType: ListingType.product,
        scope: ListingScope.international,
        priceAmount: 600,
        priceNegotiable: true,
        condition: ItemCondition.usedGood,
        images: MockPhotos.booksPhotos,
        tags: ['mock_seed', 'books', 'african', 'literature'],
        deliveryOptions: ['shipping', 'pickup'],
        contactMethod: ContactMethod.chat,
        createdAt: now.subtract(const Duration(days: 2, hours: 12)),
        communityIds: [],
      ),

      // 10. Other Products
      MarketplaceListing(
        id: '',
        sellerId: sellerId,
        sellerName: sellerName,
        sellerCity: 'Kampala',
        sellerCountryCode: 'UG',
        title: 'Solar Panel Kit 400W Complete',
        description:
            'Complete 400W solar panel kit with inverter, charge controller, batteries, and installation cables. Perfect for off-grid living.',
        category: MarketplaceCategory.otherProducts,
        subcategory: null,
        listingType: ListingType.product,
        scope: ListingScope.local,
        priceAmount: 3200,
        priceNegotiable: true,
        condition: ItemCondition.brandNew,
        images: MockPhotos.solarPhotos,
        tags: ['mock_seed', 'solar', 'energy', 'offgrid'],
        deliveryOptions: ['delivery', 'pickup'],
        contactMethod: ContactMethod.whatsapp,
        createdAt: now.subtract(const Duration(days: 3)),
        communityIds: [],
      ),

      // ─── SERVICES ──────────────────────────────────────────────────────

      // 11. Professional
      MarketplaceListing(
        id: '',
        sellerId: sellerId,
        sellerName: sellerName,
        sellerCity: 'Toronto',
        sellerCountryCode: 'CA',
        title: 'Immigration Consulting Services',
        description:
            'Licensed immigration consultant specializing in African diaspora cases. Work permits, PR applications, family sponsorship, and business immigration. 15+ years experience.',
        category: MarketplaceCategory.professional,
        subcategory: 'Consulting',
        listingType: ListingType.service,
        scope: ListingScope.international,
        priceAmount: 2500,
        priceNegotiable: true,
        serviceDetails: {
          'yearsExperience': '15',
          'serviceArea': 'Global (Remote)',
          'availability': 'Weekdays 9AM-6PM EST',
        },
        images: MockPhotos.professionalPhotos,
        tags: ['mock_seed', 'immigration', 'consulting', 'legal'],
        deliveryOptions: ['digital'],
        contactMethod: ContactMethod.phone,
        createdAt: now.subtract(const Duration(hours: 3)),
        communityIds: [],
      ),

      // 12. Tech & Digital
      MarketplaceListing(
        id: '',
        sellerId: sellerId,
        sellerName: sellerName,
        sellerCity: 'Cape Town',
        sellerCountryCode: 'ZA',
        title: 'Full-Stack Web Development',
        description:
            'Professional web and mobile app development. React, Flutter, Node.js, Firebase. We build MVPs, dashboards, and e-commerce platforms. Portfolio available.',
        category: MarketplaceCategory.techDigital,
        subcategory: 'Web Development',
        listingType: ListingType.service,
        scope: ListingScope.international,
        priceAmount: 5000,
        priceNegotiable: true,
        serviceDetails: {
          'yearsExperience': '8',
          'serviceArea': 'Remote / Global',
          'availability': 'Flexible',
        },
        images: MockPhotos.techPhotos,
        tags: ['mock_seed', 'development', 'web', 'mobile', 'flutter'],
        deliveryOptions: ['digital'],
        contactMethod: ContactMethod.chat,
        createdAt: now.subtract(const Duration(hours: 6)),
        communityIds: [],
      ),

      // 13. Education
      MarketplaceListing(
        id: '',
        sellerId: sellerId,
        sellerName: sellerName,
        sellerCity: 'New York',
        sellerCountryCode: 'US',
        title: 'Swahili Language Tutoring',
        description:
            'Learn conversational Swahili from a native speaker! 1-on-1 online sessions, beginner to advanced. Customized curriculum, cultural immersion, and exam prep.',
        category: MarketplaceCategory.education,
        subcategory: 'Language Tutoring',
        listingType: ListingType.service,
        scope: ListingScope.international,
        priceAmount: 150,
        priceNegotiable: false,
        serviceDetails: {
          'yearsExperience': '10',
          'serviceArea': 'Online / Global',
          'availability': 'Mon-Sat, Flexible hours',
        },
        images: MockPhotos.educationPhotos,
        tags: ['mock_seed', 'swahili', 'language', 'tutoring'],
        deliveryOptions: ['digital'],
        contactMethod: ContactMethod.chat,
        createdAt: now.subtract(const Duration(hours: 10)),
        communityIds: [],
      ),

      // 14. Home Services
      MarketplaceListing(
        id: '',
        sellerId: sellerId,
        sellerName: sellerName,
        sellerCity: 'Houston',
        sellerCountryCode: 'US',
        title: 'Professional Plumbing & Repairs',
        description:
            'Licensed plumber serving Houston metro. Pipe repairs, installations, water heaters, drain cleaning, and bathroom/kitchen remodeling. Same-day emergency service.',
        category: MarketplaceCategory.homeServices,
        subcategory: 'Plumbing',
        listingType: ListingType.service,
        scope: ListingScope.local,
        priceAmount: 200,
        priceNegotiable: true,
        serviceDetails: {
          'yearsExperience': '12',
          'serviceArea': 'Houston, TX metro area',
          'availability': '24/7 Emergency Available',
        },
        images: MockPhotos.homeServicePhotos,
        tags: ['mock_seed', 'plumbing', 'repairs', 'home'],
        deliveryOptions: ['pickup'],
        contactMethod: ContactMethod.phone,
        createdAt: now.subtract(const Duration(hours: 14)),
        communityIds: [],
      ),

      // 15. Transport
      MarketplaceListing(
        id: '',
        sellerId: sellerId,
        sellerName: sellerName,
        sellerCity: 'Mombasa',
        sellerCountryCode: 'KE',
        title: 'Cargo Shipping to East Africa',
        description:
            'Reliable cargo and freight services from Mombasa port. Container shipping, customs clearance, and door-to-door delivery across Kenya, Uganda, Tanzania, and Rwanda.',
        category: MarketplaceCategory.transport,
        subcategory: 'Freight',
        listingType: ListingType.service,
        scope: ListingScope.international,
        priceAmount: 3000,
        priceNegotiable: true,
        serviceDetails: {
          'yearsExperience': '20',
          'serviceArea': 'East Africa (KE, UG, TZ, RW)',
          'availability': 'Mon-Fri: 8AM-5PM EAT',
        },
        images: MockPhotos.transportPhotos,
        tags: ['mock_seed', 'cargo', 'shipping', 'logistics'],
        deliveryOptions: ['shipping'],
        contactMethod: ContactMethod.whatsapp,
        createdAt: now.subtract(const Duration(days: 1, hours: 2)),
        communityIds: [],
      ),

      // 16. Events & Catering
      MarketplaceListing(
        id: '',
        sellerId: sellerId,
        sellerName: sellerName,
        sellerCity: 'Atlanta',
        sellerCountryCode: 'US',
        title: 'African Catering for Events',
        description:
            'Full-service catering specializing in West African, East African, and fusion cuisine. Weddings, corporate events, birthdays, and cultural celebrations. Minimum 50 guests.',
        category: MarketplaceCategory.eventsCatering,
        subcategory: 'Catering',
        listingType: ListingType.service,
        scope: ListingScope.local,
        priceAmount: 1800,
        priceNegotiable: true,
        serviceDetails: {
          'yearsExperience': '7',
          'serviceArea': 'Atlanta metro, GA',
          'availability': 'Weekends & Holidays preferred',
        },
        images: MockPhotos.cateringPhotos,
        tags: ['mock_seed', 'catering', 'african food', 'events'],
        deliveryOptions: ['delivery'],
        contactMethod: ContactMethod.phone,
        createdAt: now.subtract(const Duration(days: 1, hours: 8)),
        communityIds: [],
      ),

      // 17. Financial
      MarketplaceListing(
        id: '',
        sellerId: sellerId,
        sellerName: sellerName,
        sellerCity: 'London',
        sellerCountryCode: 'GB',
        title: 'Tax Advisory for Diaspora Investors',
        description:
            'Specialist tax advisory for African diaspora investing back home. Property tax, business registration, double taxation treaties, and wealth structuring across jurisdictions.',
        category: MarketplaceCategory.financial,
        subcategory: 'Tax Advisory',
        listingType: ListingType.service,
        scope: ListingScope.international,
        priceAmount: 3500,
        priceNegotiable: true,
        serviceDetails: {
          'yearsExperience': '18',
          'serviceArea': 'UK, US, East Africa',
          'availability': 'By appointment',
        },
        images: MockPhotos.financialPhotos,
        tags: ['mock_seed', 'tax', 'finance', 'investment', 'diaspora'],
        deliveryOptions: ['digital'],
        contactMethod: ContactMethod.email,
        createdAt: now.subtract(const Duration(days: 2, hours: 4)),
        communityIds: [],
      ),

      // 18. Wellness
      MarketplaceListing(
        id: '',
        sellerId: sellerId,
        sellerName: sellerName,
        sellerCity: 'Dubai',
        sellerCountryCode: 'AE',
        title: 'Personal Training & Nutrition Plans',
        description:
            'Certified personal trainer and nutritionist. Online and in-person sessions. Custom workout programs, meal plans, and accountability coaching. Specializing in busy professionals.',
        category: MarketplaceCategory.wellness,
        subcategory: 'Personal Training',
        listingType: ListingType.service,
        scope: ListingScope.international,
        priceAmount: 800,
        priceNegotiable: false,
        serviceDetails: {
          'yearsExperience': '6',
          'serviceArea': 'Dubai (in-person) / Global (online)',
          'availability': 'Daily, 6AM-9PM GST',
        },
        images: MockPhotos.wellnessPhotos,
        tags: ['mock_seed', 'fitness', 'nutrition', 'personal training'],
        deliveryOptions: ['digital', 'pickup'],
        contactMethod: ContactMethod.whatsapp,
        createdAt: now.subtract(const Duration(days: 3, hours: 2)),
        communityIds: [],
      ),

      // 19. Travel
      MarketplaceListing(
        id: '',
        sellerId: sellerId,
        sellerName: sellerName,
        sellerCity: 'Arusha',
        sellerCountryCode: 'TZ',
        title: 'Kilimanjaro Trek & Safari Package',
        description:
            '7-day Kilimanjaro Machame Route trek + 3-day Serengeti/Ngorongoro safari. All-inclusive: guides, permits, accommodation, meals, and transport. Group discounts available.',
        category: MarketplaceCategory.travel,
        subcategory: 'Adventure Tours',
        listingType: ListingType.service,
        scope: ListingScope.international,
        priceAmount: 12000,
        priceNegotiable: true,
        serviceDetails: {
          'yearsExperience': '14',
          'serviceArea': 'Northern Tanzania',
          'availability': 'Year-round, best June-October',
        },
        images: MockPhotos.travelPhotos,
        tags: ['mock_seed', 'kilimanjaro', 'safari', 'tanzania', 'travel'],
        deliveryOptions: ['pickup'],
        contactMethod: ContactMethod.whatsapp,
        createdAt: now.subtract(const Duration(days: 4)),
        communityIds: [],
      ),

      // 20. Other Services
      MarketplaceListing(
        id: '',
        sellerId: sellerId,
        sellerName: sellerName,
        sellerCity: 'Minneapolis',
        sellerCountryCode: 'US',
        title: 'Amharic & Somali Translation Services',
        description:
            'Professional translation and interpretation services for Amharic and Somali. Legal documents, medical visits, business meetings, and academic papers. Certified translator.',
        category: MarketplaceCategory.otherServices,
        subcategory: 'Translation',
        listingType: ListingType.service,
        scope: ListingScope.international,
        priceAmount: 250,
        priceNegotiable: true,
        serviceDetails: {
          'yearsExperience': '9',
          'serviceArea': 'Minneapolis (in-person) / Global (remote)',
          'availability': 'Mon-Sat 8AM-8PM CST',
        },
        images: MockPhotos.translationPhotos,
        tags: ['mock_seed', 'translation', 'amharic', 'somali'],
        deliveryOptions: ['digital'],
        contactMethod: ContactMethod.chat,
        createdAt: now.subtract(const Duration(days: 5)),
        communityIds: [],
      ),

      // ─── JOBS ───────────────────────────────────────────────────────────

      // 21. Technology
      MarketplaceListing(
        id: '',
        sellerId: sellerId,
        sellerName: sellerName,
        sellerCity: 'San Francisco',
        sellerCountryCode: 'US',
        title: 'Senior Flutter Developer – Remote',
        description:
            'We are hiring a Senior Flutter Developer to join our fintech startup building cross-border payment solutions for the African diaspora. Must have 4+ years Flutter experience, Dart proficiency, and REST/GraphQL API integration skills. Fully remote, competitive salary + equity.',
        category: MarketplaceCategory.jobTechnology,
        subcategory: 'Software Engineering',
        listingType: ListingType.job,
        scope: ListingScope.international,
        priceAmount: 120000,
        priceNegotiable: false,
        jobDetails: {
          'employmentType': 'Full-time',
          'salaryRange': '\$110K – \$130K / year',
          'experienceLevel': 'Senior (4+ years)',
          'workMode': 'Remote',
          'applicationDeadline': 'Open until filled',
          'companyName': 'DiasPay Inc.',
        },
        images: MockPhotos.jobTechPhotos,
        tags: ['mock_seed', 'flutter', 'developer', 'remote', 'fintech'],
        contactMethod: ContactMethod.email,
        createdAt: now.subtract(const Duration(hours: 3)),
        communityIds: [],
      ),

      // 22. Healthcare
      MarketplaceListing(
        id: '',
        sellerId: sellerId,
        sellerName: sellerName,
        sellerCity: 'London',
        sellerCountryCode: 'GB',
        title: 'Registered Nurse – NHS Hospital',
        description:
            'NHS Trust seeking qualified Registered Nurses for their Acute Medical Unit. Visa sponsorship available for international candidates. Band 5-6 position with excellent training opportunities, pension scheme, and career progression.',
        category: MarketplaceCategory.jobHealthcare,
        subcategory: 'Nursing',
        listingType: ListingType.job,
        scope: ListingScope.international,
        priceAmount: 35000,
        priceNegotiable: false,
        jobDetails: {
          'employmentType': 'Full-time',
          'salaryRange': '£28K – £40K / year',
          'experienceLevel': 'Mid-level (2+ years)',
          'workMode': 'On-site',
          'applicationDeadline': '2026-04-30',
          'companyName': 'NHS Greater London Trust',
          'visaSponsorship': 'Yes',
        },
        images: MockPhotos.jobHealthcarePhotos,
        tags: ['mock_seed', 'nurse', 'nhs', 'healthcare', 'visa'],
        contactMethod: ContactMethod.email,
        createdAt: now.subtract(const Duration(hours: 6)),
        communityIds: [],
      ),

      // 23. Finance
      MarketplaceListing(
        id: '',
        sellerId: sellerId,
        sellerName: sellerName,
        sellerCity: 'Toronto',
        sellerCountryCode: 'CA',
        title: 'Financial Analyst – Investment Banking',
        description:
            'Major Canadian bank is hiring a Financial Analyst to join their Investment Banking division. Strong modelling skills, CFA Level I or II preferred. Experience with African markets is a plus. Hybrid work model.',
        category: MarketplaceCategory.jobFinance,
        subcategory: 'Financial Analysis',
        listingType: ListingType.job,
        scope: ListingScope.local,
        priceAmount: 85000,
        priceNegotiable: false,
        jobDetails: {
          'employmentType': 'Full-time',
          'salaryRange': 'CAD \$80K – \$95K / year',
          'experienceLevel': 'Mid-level (2-4 years)',
          'workMode': 'Hybrid',
          'applicationDeadline': '2026-03-31',
          'companyName': 'Scotiabank',
        },
        images: MockPhotos.jobFinancePhotos,
        tags: ['mock_seed', 'finance', 'banking', 'analyst'],
        contactMethod: ContactMethod.email,
        createdAt: now.subtract(const Duration(hours: 8)),
        communityIds: [],
      ),

      // 24. Engineering
      MarketplaceListing(
        id: '',
        sellerId: sellerId,
        sellerName: sellerName,
        sellerCity: 'Lagos',
        sellerCountryCode: 'NG',
        title: 'Civil Engineer – Infrastructure Projects',
        description:
            'Leading construction firm hiring a Civil Engineer to oversee major infrastructure projects across West Africa. PE certification required. Relocation assistance and housing provided. Competitive package with hardship allowance.',
        category: MarketplaceCategory.jobEngineering,
        subcategory: 'Civil',
        listingType: ListingType.job,
        scope: ListingScope.international,
        priceAmount: 65000,
        priceNegotiable: true,
        jobDetails: {
          'employmentType': 'Full-time',
          'salaryRange': '\$55K – \$75K / year + housing',
          'experienceLevel': 'Senior (5+ years)',
          'workMode': 'On-site',
          'applicationDeadline': '2026-05-15',
          'companyName': 'Julius Berger Nigeria',
        },
        images: MockPhotos.jobEngineeringPhotos,
        tags: ['mock_seed', 'engineer', 'civil', 'infrastructure'],
        contactMethod: ContactMethod.phone,
        createdAt: now.subtract(const Duration(days: 1)),
        communityIds: [],
      ),

      // 25. Education
      MarketplaceListing(
        id: '',
        sellerId: sellerId,
        sellerName: sellerName,
        sellerCity: 'Dubai',
        sellerCountryCode: 'AE',
        title: 'Maths Teacher – International School',
        description:
            'British curriculum international school in Dubai seeking a qualified Maths Teacher for GCSE and A-Level classes. Tax-free salary, accommodation, flights, and medical insurance included. QTS or equivalent required.',
        category: MarketplaceCategory.jobEducation,
        subcategory: 'Teaching',
        listingType: ListingType.job,
        scope: ListingScope.international,
        priceAmount: 50000,
        priceNegotiable: false,
        jobDetails: {
          'employmentType': 'Full-time',
          'salaryRange': 'AED 12K – 18K / month (tax-free)',
          'experienceLevel': 'Mid-level (2+ years)',
          'workMode': 'On-site',
          'applicationDeadline': '2026-04-01',
          'companyName': 'GEMS Education',
        },
        images: MockPhotos.jobEducationPhotos,
        tags: ['mock_seed', 'teacher', 'maths', 'dubai', 'international'],
        contactMethod: ContactMethod.email,
        createdAt: now.subtract(const Duration(days: 1, hours: 4)),
        communityIds: [],
      ),

      // 26. Marketing
      MarketplaceListing(
        id: '',
        sellerId: sellerId,
        sellerName: sellerName,
        sellerCity: 'Nairobi',
        sellerCountryCode: 'KE',
        title: 'Digital Marketing Manager – East Africa',
        description:
            'Fast-growing e-commerce platform seeks a Digital Marketing Manager to lead paid acquisition, SEO, and content strategy across East Africa. Must understand the African consumer landscape. Hybrid role with travel.',
        category: MarketplaceCategory.jobMarketing,
        subcategory: 'Digital Marketing',
        listingType: ListingType.job,
        scope: ListingScope.local,
        priceAmount: 40000,
        priceNegotiable: true,
        jobDetails: {
          'employmentType': 'Full-time',
          'salaryRange': 'KES 350K – 500K / month',
          'experienceLevel': 'Senior (4+ years)',
          'workMode': 'Hybrid',
          'applicationDeadline': '2026-03-15',
          'companyName': 'Jumia Kenya',
        },
        images: MockPhotos.jobMarketingPhotos,
        tags: ['mock_seed', 'marketing', 'digital', 'ecommerce'],
        contactMethod: ContactMethod.email,
        createdAt: now.subtract(const Duration(days: 2)),
        communityIds: [],
      ),

      // 27. Sales
      MarketplaceListing(
        id: '',
        sellerId: sellerId,
        sellerName: sellerName,
        sellerCity: 'Johannesburg',
        sellerCountryCode: 'ZA',
        title: 'Business Development Rep – SaaS',
        description:
            'B2B SaaS company expanding into African markets needs a Business Development Representative. You\'ll identify leads, run demos, and close deals. OTE of R800K+. Base + commission structure.',
        category: MarketplaceCategory.jobSales,
        subcategory: 'Business Development',
        listingType: ListingType.job,
        scope: ListingScope.local,
        priceAmount: 45000,
        priceNegotiable: false,
        jobDetails: {
          'employmentType': 'Full-time',
          'salaryRange': 'ZAR 35K – 55K / month + commission',
          'experienceLevel': 'Entry to Mid-level',
          'workMode': 'Hybrid',
          'applicationDeadline': 'Open until filled',
          'companyName': 'Paystack',
        },
        images: MockPhotos.jobSalesPhotos,
        tags: ['mock_seed', 'sales', 'saas', 'business'],
        contactMethod: ContactMethod.chat,
        createdAt: now.subtract(const Duration(days: 2, hours: 5)),
        communityIds: [],
      ),

      // 28. Customer Service
      MarketplaceListing(
        id: '',
        sellerId: sellerId,
        sellerName: sellerName,
        sellerCity: 'Accra',
        sellerCountryCode: 'GH',
        title: 'Customer Support Agent – Bilingual (French/English)',
        description:
            'International call centre hiring bilingual Customer Support Agents. Handle customer enquiries via phone, chat, and email. Night shift premium available. Training provided. Start immediately.',
        category: MarketplaceCategory.jobCustomerService,
        subcategory: 'Call Center',
        listingType: ListingType.job,
        scope: ListingScope.local,
        priceAmount: 8000,
        priceNegotiable: false,
        jobDetails: {
          'employmentType': 'Full-time',
          'salaryRange': 'GHS 3,500 – 5,000 / month',
          'experienceLevel': 'Entry-level',
          'workMode': 'On-site',
          'applicationDeadline': '2026-03-01',
          'companyName': 'Teleperformance Ghana',
        },
        images: MockPhotos.jobCustomerServicePhotos,
        tags: ['mock_seed', 'customer-service', 'bilingual', 'french'],
        contactMethod: ContactMethod.phone,
        createdAt: now.subtract(const Duration(days: 3)),
        communityIds: [],
      ),

      // 29. Admin & HR
      MarketplaceListing(
        id: '',
        sellerId: sellerId,
        sellerName: sellerName,
        sellerCity: 'Houston',
        sellerCountryCode: 'US',
        title: 'HR Coordinator – Diaspora Non-Profit',
        description:
            'Non-profit organization supporting the African diaspora community is hiring an HR Coordinator. Manage recruitment, on-boarding, benefits admin, and employee relations. Passion for community impact required.',
        category: MarketplaceCategory.jobAdminHR,
        subcategory: 'HR Management',
        listingType: ListingType.job,
        scope: ListingScope.local,
        priceAmount: 55000,
        priceNegotiable: false,
        jobDetails: {
          'employmentType': 'Full-time',
          'salaryRange': '\$50K – \$60K / year',
          'experienceLevel': 'Mid-level (2+ years)',
          'workMode': 'Hybrid',
          'applicationDeadline': '2026-03-20',
          'companyName': 'African Diaspora Foundation',
        },
        images: MockPhotos.jobHRPhotos,
        tags: ['mock_seed', 'hr', 'nonprofit', 'coordinator'],
        contactMethod: ContactMethod.email,
        createdAt: now.subtract(const Duration(days: 3, hours: 6)),
        communityIds: [],
      ),

      // 30. Construction
      MarketplaceListing(
        id: '',
        sellerId: sellerId,
        sellerName: sellerName,
        sellerCity: 'Kigali',
        sellerCountryCode: 'RW',
        title: 'Electrician – Commercial Building Project',
        description:
            'Hiring a licensed Electrician for a 6-month commercial building project in Kigali Innovation City. Must have experience with three-phase wiring and building management systems. Accommodation included.',
        category: MarketplaceCategory.jobConstruction,
        subcategory: 'Electricians',
        listingType: ListingType.job,
        scope: ListingScope.local,
        priceAmount: 18000,
        priceNegotiable: true,
        jobDetails: {
          'employmentType': 'Contract (6 months)',
          'salaryRange': 'RWF 800K – 1.2M / month',
          'experienceLevel': 'Mid-level (3+ years)',
          'workMode': 'On-site',
          'applicationDeadline': '2026-03-10',
          'companyName': 'Rwanda Development Board',
        },
        images: MockPhotos.jobConstructionPhotos,
        tags: ['mock_seed', 'electrician', 'construction', 'kigali'],
        contactMethod: ContactMethod.phone,
        createdAt: now.subtract(const Duration(days: 4)),
        communityIds: [],
      ),

      // 31. Transport & Logistics
      MarketplaceListing(
        id: '',
        sellerId: sellerId,
        sellerName: sellerName,
        sellerCity: 'Atlanta',
        sellerCountryCode: 'US',
        title: 'CDL Truck Driver – Long-Haul Routes',
        description:
            'Trucking company hiring CDL-A drivers for long-haul routes across the Southeast US. Consistent miles, weekly home time, modern equipment. Sign-on bonus of \$5,000 for experienced drivers.',
        category: MarketplaceCategory.jobTransportLogistics,
        subcategory: 'Driving',
        listingType: ListingType.job,
        scope: ListingScope.local,
        priceAmount: 72000,
        priceNegotiable: false,
        jobDetails: {
          'employmentType': 'Full-time',
          'salaryRange': '\$65K – \$80K / year',
          'experienceLevel': 'Mid-level (1+ years CDL)',
          'workMode': 'On-the-road',
          'applicationDeadline': 'Open until filled',
          'companyName': 'Sahara Freight LLC',
        },
        images: MockPhotos.jobTransportPhotos,
        tags: ['mock_seed', 'driver', 'cdl', 'trucking'],
        contactMethod: ContactMethod.phone,
        createdAt: now.subtract(const Duration(days: 4, hours: 8)),
        communityIds: [],
      ),

      // 32. Hospitality
      MarketplaceListing(
        id: '',
        sellerId: sellerId,
        sellerName: sellerName,
        sellerCity: 'Paris',
        sellerCountryCode: 'FR',
        title: 'Head Chef – West African Cuisine Restaurant',
        description:
            'Upscale West African restaurant opening in the 10th arrondissement seeks an experienced Head Chef. Must have deep knowledge of Jollof, Suya, Egusi, and modern African fusion. Michelin-aspiring kitchen.',
        category: MarketplaceCategory.jobHospitality,
        subcategory: 'Restaurant',
        listingType: ListingType.job,
        scope: ListingScope.international,
        priceAmount: 42000,
        priceNegotiable: true,
        jobDetails: {
          'employmentType': 'Full-time',
          'salaryRange': '€3,200 – €4,500 / month',
          'experienceLevel': 'Senior (5+ years)',
          'workMode': 'On-site',
          'applicationDeadline': '2026-04-15',
          'companyName': 'Mama Africa Paris',
        },
        images: MockPhotos.jobHospitalityPhotos,
        tags: ['mock_seed', 'chef', 'restaurant', 'african-cuisine'],
        contactMethod: ContactMethod.whatsapp,
        createdAt: now.subtract(const Duration(days: 5)),
        communityIds: [],
      ),

      // 33. Retail
      MarketplaceListing(
        id: '',
        sellerId: sellerId,
        sellerName: sellerName,
        sellerCity: 'Dallas',
        sellerCountryCode: 'US',
        title: 'Store Manager – African Grocery Market',
        description:
            'Family-owned African grocery store chain expanding to a new location. Hiring a Store Manager to oversee operations, inventory, staff scheduling, and customer experience. Knowledge of African food products essential.',
        category: MarketplaceCategory.jobRetail,
        subcategory: 'Store Management',
        listingType: ListingType.job,
        scope: ListingScope.local,
        priceAmount: 48000,
        priceNegotiable: true,
        jobDetails: {
          'employmentType': 'Full-time',
          'salaryRange': '\$42K – \$55K / year',
          'experienceLevel': 'Mid-level (2+ years retail)',
          'workMode': 'On-site',
          'applicationDeadline': '2026-03-25',
          'companyName': 'Mama\'s African Market',
        },
        images: MockPhotos.jobRetailPhotos,
        tags: ['mock_seed', 'retail', 'manager', 'grocery'],
        contactMethod: ContactMethod.chat,
        createdAt: now.subtract(const Duration(days: 5, hours: 4)),
        communityIds: [],
      ),

      // 34. Creative & Media
      MarketplaceListing(
        id: '',
        sellerId: sellerId,
        sellerName: sellerName,
        sellerCity: 'Kampala',
        sellerCountryCode: 'UG',
        title: 'Video Producer – Afrobeats Music Label',
        description:
            'Award-winning Afrobeats label seeks a Video Producer to create music videos, behind-the-scenes content, and social media campaigns. Must have a strong portfolio and experience with high-end video production.',
        category: MarketplaceCategory.jobCreativeMedia,
        subcategory: 'Video Production',
        listingType: ListingType.job,
        scope: ListingScope.international,
        priceAmount: 30000,
        priceNegotiable: true,
        jobDetails: {
          'employmentType': 'Freelance / Contract',
          'salaryRange': 'UGX 8M – 15M / project',
          'experienceLevel': 'Mid-level (3+ years)',
          'workMode': 'Hybrid',
          'applicationDeadline': 'Open until filled',
          'companyName': 'Swangz Avenue',
        },
        images: MockPhotos.jobCreativePhotos,
        tags: ['mock_seed', 'video', 'producer', 'afrobeats', 'music'],
        contactMethod: ContactMethod.whatsapp,
        createdAt: now.subtract(const Duration(days: 6)),
        communityIds: [],
      ),

      // 35. Other Jobs
      MarketplaceListing(
        id: '',
        sellerId: sellerId,
        sellerName: sellerName,
        sellerCity: 'Berlin',
        sellerCountryCode: 'DE',
        title: 'Community Organiser Intern – Diaspora Network',
        description:
            'Paid internship (6 months) for a passionate individual to help build community events, manage social channels, and coordinate volunteer programs for the African diaspora community in Berlin. German language a plus.',
        category: MarketplaceCategory.jobOther,
        subcategory: 'Internship',
        listingType: ListingType.job,
        scope: ListingScope.local,
        priceAmount: 15000,
        priceNegotiable: false,
        jobDetails: {
          'employmentType': 'Internship (6 months)',
          'salaryRange': '€1,200 / month stipend',
          'experienceLevel': 'Entry-level / Student',
          'workMode': 'Hybrid',
          'applicationDeadline': '2026-03-30',
          'companyName': 'ADNE Berlin e.V.',
        },
        images: MockPhotos.jobInternPhotos,
        tags: ['mock_seed', 'intern', 'community', 'nonprofit'],
        contactMethod: ContactMethod.email,
        createdAt: now.subtract(const Duration(days: 7)),
        communityIds: [],
      ),
    ];
  }
}
