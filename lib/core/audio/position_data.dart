class PositionData {
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;

  const PositionData(
    this.position,
    this.bufferedPosition,
    this.duration,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PositionData &&
          runtimeType == other.runtimeType &&
          position == other.position &&
          bufferedPosition == other.bufferedPosition &&
          duration == other.duration;

  @override
  int get hashCode =>
      position.hashCode ^ bufferedPosition.hashCode ^ duration.hashCode;

  @override
  String toString() =>
      'PositionData(position: $position, bufferedPosition: $bufferedPosition, duration: $duration)';
}
