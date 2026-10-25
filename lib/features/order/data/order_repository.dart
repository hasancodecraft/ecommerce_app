import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_exceptions.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/preference_service.dart';
import '../models/order_model.dart';

abstract class OrderRepository {
  Future<OrderModel> placeOrder(OrderModel order);
  Future<List<OrderModel>> getOrders({int? userId});
  Future<OrderModel> getOrderById(String orderId);
}

class OrderRepositoryImpl implements OrderRepository {
  final DioClient dioClient;
  final PreferenceService preferenceService;

  OrderRepositoryImpl({
    required this.dioClient,
    required this.preferenceService,
  });

  List<OrderModel> _getSavedOrders() {
    final saved = preferenceService.getCachedOrders();
    final orders = <OrderModel>[];
    for (final item in saved) {
      try {
        orders.add(OrderModel.fromJson(item));
      } catch (_) {
        // An old or incomplete cache record should not break the app.
      }
    }
    return orders;
  }

  Future<void> _saveOrder(OrderModel order) async {
    final orders = _getSavedOrders();
    orders.removeWhere((item) => item.id == order.id);
    orders.insert(0, order);
    await preferenceService.setCachedOrders(
      orders.map((item) => item.toJson()).toList(),
    );
  }

  @override
  Future<OrderModel> placeOrder(OrderModel order) async {
    try {
      final response = await dioClient.post(
        ApiConstants.ordersEndpoint,
        data: order.toJson(),
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        final placed = OrderModel.fromJson(
          Map<String, dynamic>.from(response.data as Map),
        );
        await _saveOrder(placed);
        return placed;
      }
      throw ApiException('Could not place order. Please try again.');
    } on NetworkException {
      // The course's local json-server may not be running. Store the order
      // on this device instead of silently pretending it reached a server.
      final localOrder = order.copyWith(status: 'saved locally');
      await _saveOrder(localOrder);
      return localOrder;
    }
  }

  @override
  Future<List<OrderModel>> getOrders({int? userId}) async {
    final savedOrders = _getSavedOrders();
    final allOrders = <String, OrderModel>{};

    for (final order in savedOrders) {
      if (userId == null || order.userId == userId) {
        allOrders[order.id] = order;
      }
    }

    try {
      final response = await dioClient.get(
        ApiConstants.ordersEndpoint,
        queryParameters: userId != null ? {'userId': userId} : null,
      );
      if (response.statusCode == 200 && response.data is List) {
        final remoteOrders = <OrderModel>[];
        for (final item in response.data as List) {
          try {
            final order = OrderModel.fromJson(
              Map<String, dynamic>.from(item as Map),
            );
            // Never display another customer's order.
            if (userId == null || order.userId == userId) {
              allOrders[order.id] = order;
              remoteOrders.add(order);
            }
          } catch (_) {
            // Skip an invalid order without losing the rest of the history.
          }
        }
        for (final order in remoteOrders) {
          await _saveOrder(order);
        }
      }
    } on NetworkException {
      // Saved history can still be viewed while the local server is offline.
    }

    final result = allOrders.values.toList();
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  @override
  Future<OrderModel> getOrderById(String orderId) async {
    for (final order in _getSavedOrders()) {
      if (order.id == orderId) return order;
    }
    try {
      final response = await dioClient.get(
        '${ApiConstants.ordersEndpoint}/$orderId',
      );
      return OrderModel.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on NetworkException {
      throw const NotFoundException('Order is not saved on this device.');
    }
  }
}
