enum BookingStatus {
  booked('Booked'),
  technicianAssigned('Technician Assigned'),
  accepted('Accepted'),
  onTheWay('On The Way'),
  arrived('Arrived'),
  estimateSent('Estimate Sent'),
  estimateApproved('Estimate Approved'),
  serviceStarted('Service Started'),
  serviceCompleted('Service Completed'),
  billGenerated('Bill Generated'),
  closed('Closed');

  const BookingStatus(this.label);
  final String label;

  static BookingStatus fromString(String value) {
    return BookingStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => BookingStatus.booked,
    );
  }
}
