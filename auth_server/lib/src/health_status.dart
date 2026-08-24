/// Public liveness response. Configuration and dependency state remain private
/// because they can help an attacker profile the deployment.
Map<String, dynamic> buildHealthStatus() => {'ok': true};
