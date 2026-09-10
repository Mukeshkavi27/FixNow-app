class AppConstants {
  static const whatsappSupportNumber = '+919999999999';

  static const applianceCategories = [
    ApplianceCategory(
      'Air Conditioner',
      'Starting at Rs. 499',
      'assets/images/service_ac_uniform_v2.jpg',
    ),
    ApplianceCategory(
      'Refrigerator',
      'Starting at Rs. 399',
      'assets/images/service_refrigerator_uniform_v2.jpg',
    ),
    ApplianceCategory(
      'Washing Machine',
      'Starting at Rs. 449',
      'assets/images/service_washing_machine_uniform_v2.jpg',
    ),
    ApplianceCategory(
      'Microwave',
      'Starting at Rs. 299',
      'assets/images/service_microwave_uniform_v2.jpg',
    ),
    ApplianceCategory(
      'Water Purifier',
      'Starting at Rs. 349',
      'assets/images/service_water_purifier_uniform_v2.jpg',
    ),
    ApplianceCategory(
      'Television',
      'Starting at Rs. 399',
      'assets/images/service_television_uniform_v2.jpg',
    ),
    ApplianceCategory(
      'Fan',
      'Starting at Rs. 199',
      'assets/images/service_fan_uniform_v2.jpg',
    ),
    ApplianceCategory(
      'Other Appliances',
      'Starting at Rs. 249',
      'assets/images/service_other_uniform_v2.jpg',
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
