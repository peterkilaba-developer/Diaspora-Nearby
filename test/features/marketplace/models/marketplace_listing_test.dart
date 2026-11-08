import 'package:flutter_test/flutter_test.dart';
import 'package:diaspora_nearby/features/marketplace/models/marketplace_listing.dart';
import 'package:diaspora_nearby/features/marketplace/widgets/marketplace_card_helpers.dart';

void main() {
  group('MarketplaceListing.fromMap normalization & bug fixes', () {
    test('strips deliveryOptions and condition for Job listings and empty strings in jobDetails', () {
      final listing = MarketplaceListing.fromMap({
        'sellerId': 'u1',
        'sellerName': 'Peter Swai',
        'title': 'Blockchain Developer',
        'description': 'Blockchain Developer role at Diaspora Nearby.',
        'category': MarketplaceCategory.jobTechnology,
        'subcategory': 'Software Engineering',
        'listingType': ListingType.job,
        'scope': 'global',
        'priceAmount': 0,
        'isNegotiable': true,
        'condition': ItemCondition.brandNew,
        'deliveryOptions': ['pickup'],
        'contactMethod': 'in_app',
        'saveCount': 4,
        'jobDetails': {
          'companyName': 'Diaspora Nearby',
          'employmentType': 'Full-time',
          'salaryRange': '\$100,000/year',
          'experienceLevel': 'mid',
          'workMode': 'Remote',
          'applicationDeadline': '',
        },
        'location': {
          'city': 'Mason City',
          'country': 'United States',
          'countryCode': 'US',
        },
      }, 'job_1');

      expect(listing.listingType, ListingType.job);
      expect(listing.deliveryOptions, isNull);
      expect(listing.condition, isNull);
      expect(listing.scope, ListingScope.international);
      expect(listing.contactMethod, ContactMethod.chat);
      expect(listing.priceNegotiable, isTrue);
      expect(listing.savedCount, 4);
      expect(listing.jobDetails, isNotNull);
      expect(listing.jobDetails!['experienceLevel'], 'Mid-Level (3-5 yrs)');
      expect(listing.jobDetails!.containsKey('applicationDeadline'), isFalse);
    });

    test('strips deliveryOptions and condition for Service and Real Estate listings', () {
      final serviceListing = MarketplaceListing.fromMap({
        'sellerId': 'u1',
        'sellerName': 'Alice',
        'title': 'Tax Advisory',
        'description': 'Cross-border tax filing',
        'category': MarketplaceCategory.professional,
        'listingType': ListingType.service,
        'deliveryOptions': ['pickup'],
        'condition': ItemCondition.brandNew,
        'serviceDetails': {
          'experience': '5 years',
          'serviceArea': '',
        },
        'location': {'city': 'London', 'country': 'UK', 'countryCode': 'GB'},
      }, 'svc_1');

      expect(serviceListing.deliveryOptions, isNull);
      expect(serviceListing.condition, isNull);
      expect(serviceListing.serviceDetails!['experience'], '5 years');
      expect(serviceListing.serviceDetails!.containsKey('serviceArea'), isFalse);
      expect(getCategorySpecs(serviceListing), '5 years experience');

      final realEstateListing = MarketplaceListing.fromMap({
        'sellerId': 'u1',
        'sellerName': 'Bob',
        'title': '3 Bedroom Property For Sale',
        'description': 'Spacious home',
        'category': MarketplaceCategory.realEstate,
        'listingType': ListingType.product,
        'deliveryOptions': ['pickup'],
        'condition': ItemCondition.usedGood,
        'realEstateDetails': {
          'type': 'sale',
          'bedrooms': '3',
          'bathrooms': '',
          'sqft': '',
        },
        'location': {'city': 'Nairobi', 'country': 'Kenya', 'countryCode': 'KE'},
      }, 're_1');

      expect(realEstateListing.deliveryOptions, isNull);
      expect(realEstateListing.condition, isNull);
      expect(realEstateListing.realEstateDetails!['bedrooms'], '3');
      expect(realEstateListing.realEstateDetails!.containsKey('bathrooms'), isFalse);
      expect(getCategorySpecs(realEstateListing), '3 bed');
    });

    test('preserves deliveryOptions and condition for physical Product listings', () {
      final productListing = MarketplaceListing.fromMap({
        'sellerId': 'u1',
        'sellerName': 'Seller',
        'title': 'iPhone 15 Pro 256GB',
        'description': 'Unlocked',
        'category': MarketplaceCategory.electronics,
        'listingType': ListingType.product,
        'condition': ItemCondition.likeNew,
        'deliveryOptions': ['pickup', 'shipping'],
        'electronicsDetails': {
          'brand': 'Apple',
          'model': 'iPhone 15 Pro',
          'storage': '256GB',
        },
        'location': {'city': 'Dallas', 'country': 'US', 'countryCode': 'US'},
      }, 'prod_1');

      expect(productListing.deliveryOptions, ['pickup', 'shipping']);
      expect(productListing.condition, ItemCondition.likeNew);
      expect(DeliveryOption.displayName('pickup'), 'Pickup');
      expect(getCategorySpecs(productListing), 'Apple · 256GB · Like New');
    });
  });
}
