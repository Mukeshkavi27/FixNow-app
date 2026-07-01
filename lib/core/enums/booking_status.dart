enum BookingStatus {
  booked('Waiting for Admin Review'),
  technicianAssigned('Technician Assigned'),
  accepted('Accepted'),
  onTheWay('On The Way'),
  arrived('Technician Started Work'),
  estimateSent('Waiting for Customer Approval'),
  estimateRejected('Estimate Rejected'),
  estimateApproved('Customer Approved'),
  serviceStarted('Work In Progress'),
  onHold('On Hold'),
  serviceCompleted('Completed'),
  billGenerated('Final Bill Generated'),
  closed('Payment Completed');

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
      BookingStatus.estimateSent => next == BookingStatus.estimateApproved ||
          next == BookingStatus.estimateRejected,
      BookingStatus.estimateRejected => next == BookingStatus.estimateSent,
      BookingStatus.estimateApproved => next == BookingStatus.serviceStarted,
      BookingStatus.serviceStarted =>
        next == BookingStatus.serviceCompleted || next == BookingStatus.onHold,
      BookingStatus.onHold => next == BookingStatus.technicianAssigned,
      BookingStatus.serviceCompleted => next == BookingStatus.billGenerated,
      BookingStatus.billGenerated => next == BookingStatus.closed,
      BookingStatus.closed => false,
    };
  }
}
