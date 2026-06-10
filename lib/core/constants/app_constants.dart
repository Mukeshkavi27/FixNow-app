class AppConstants {
  static const whatsappSupportNumber = '+919999999999';

  static const applianceCategories = [
    ApplianceCategory('Air Conditioner', 'Starting at Rs. 499', 'ac.png'),
    ApplianceCategory('Refrigerator', 'Starting at Rs. 399', 'refrigerator.png'),
    ApplianceCategory('Washing Machine', 'Starting at Rs. 449', 'washing_machine.png'),
    ApplianceCategory('Microwave', 'Starting at Rs. 299', 'microwave.png'),
    ApplianceCategory('Water Purifier', 'Starting at Rs. 349', 'water_purifier.png'),
    ApplianceCategory('Television', 'Starting at Rs. 399', 'television.png'),
    ApplianceCategory('Fan', 'Starting at Rs. 199', 'fan.png'),
    ApplianceCategory('Other Appliances', 'Starting at Rs. 249', 'other.png'),
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
