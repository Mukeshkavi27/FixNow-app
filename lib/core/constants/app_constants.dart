class AppConstants {
  static const whatsappSupportNumber = '+919999999999';

  static const applianceCategories = [
    ApplianceCategory(
      'Air Conditioner',
      'Starting at Rs. 499',
      'assets/images/ac.png',
    ),
    ApplianceCategory(
      'Refrigerator',
      'Starting at Rs. 399',
      'assets/images/refrigerator.png',
    ),
    ApplianceCategory(
      'Washing Machine',
      'Starting at Rs. 449',
      'assets/images/washing_machine.png',
    ),
    ApplianceCategory(
      'Microwave',
      'Starting at Rs. 299',
      'assets/images/microwave.png',
    ),
    ApplianceCategory(
      'Water Purifier',
      'Starting at Rs. 349',
      'assets/images/water_purifier.png',
    ),
    ApplianceCategory(
      'Television',
      'Starting at Rs. 399',
      'assets/images/television.png',
    ),
    ApplianceCategory(
      'Fan',
      'Starting at Rs. 199',
      'assets/images/fan.png',
    ),
    ApplianceCategory(
      'Other Appliances',
      'Starting at Rs. 249',
      'assets/images/other_services.png',
    ),
  ];
}

class ApplianceCategory {
  const ApplianceCategory(
    this.name,
    this.startingPrice,
    this.assetName, {
    this.imageUrl,
    this.startingPriceValue,
  });

  final String name;
  final String startingPrice;
  final String assetName;
  final String? imageUrl;
  final double? startingPriceValue;
}
