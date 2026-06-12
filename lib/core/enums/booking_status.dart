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

  bool canTransitionTo(BookingStatus next) {
    return switch (this) {
      BookingStatus.booked => next == BookingStatus.technicianAssigned,
      BookingStatus.technicianAssigned => next == BookingStatus.accepted,
      BookingStatus.accepted => next == BookingStatus.onTheWay,
      BookingStatus.onTheWay => next == BookingStatus.arrived,
      BookingStatus.arrived => next == BookingStatus.estimateSent,
      BookingStatus.estimateSent => next == BookingStatus.estimateApproved,
      BookingStatus.estimateApproved => next == BookingStatus.serviceStarted,
      BookingStatus.serviceStarted => next == BookingStatus.serviceCompleted,
      BookingStatus.serviceCompleted => next == BookingStatus.billGenerated,
      BookingStatus.billGenerated => next == BookingStatus.closed,
      BookingStatus.closed => false,
    };
  }
}
