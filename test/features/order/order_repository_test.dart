import 'package:dio/dio.dart';
import 'package:ecommerce_app/core/network/dio_client.dart';
import 'package:ecommerce_app/core/storage/preference_service.dart';
import 'package:ecommerce_app/features/cart/models/cart_item.dart';
import 'package:ecommerce_app/features/order/data/order_repository.dart';
import 'package:ecommerce_app/features/order/models/order_model.dart';
import 'package:ecommerce_app/features/order/models/payment_method.dart';
import 'package:ecommerce_app/features/order/models/shipping_address_model.dart';
import 'package:ecommerce_app/features/product/models/product.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DemoOrdersApi extends Interceptor {
  bool offline = false;
  final List<Map<String, dynamic>> orders = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (offline) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          message: 'Local server is not running',
        ),
      );
      return;
    }

    if (options.method == 'POST') {
      final order = Map<String, dynamic>.from(options.data as Map);
      orders.add(order);
      handler.resolve(
        Response(requestOptions: options, statusCode: 201, data: order),
      );
      return;
    }

    if (options.method == 'GET') {
      handler.resolve(
        Response(requestOptions: options, statusCode: 200, data: orders),
      );
      return;
    }

    handler.next(options);
  }
}

OrderModel sampleOrder({String id = 'EVR-TEST-1', int userId = 7}) {
  return OrderModel(
    id: id,
    userId: userId,
    items: const [
      CartItem(product: Product(id: 1, title: 'Test Product', price: 25), quantity: 2),
    ],
    subtotal: 50,
    tax: 4,
    total: 54,
    shippingAddress: const ShippingAddressModel(
      fullName: 'Test Customer',
      addressLine: 'Test Road',
      city: 'Dhaka',
      postalCode: '1200',
      phone: '01234567890',
    ),
    paymentMethod: PaymentMethod.cashOnDelivery,
    status: 'confirmed',
    createdAt: DateTime(2026, 10, 25),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PreferenceService preferences;
  late DemoOrdersApi server;
  late OrderRepositoryImpl repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await PreferenceService.init();
    server = DemoOrdersApi();
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost:3001'));
    dio.interceptors.add(server);
    repository = OrderRepositoryImpl(
      dioClient: DioClient(preferenceService: preferences, dio: dio),
      preferenceService: preferences,
    );
  });

  test('places order on mock server and saves a local copy', () async {
    final placed = await repository.placeOrder(sampleOrder());
    expect(placed.status, 'confirmed');
    expect(server.orders.length, 1);
    expect(preferences.getCachedOrders().length, 1);
    final history = await repository.getOrders(userId: 7);
    expect(history.length, 1);
    expect(history.first.id, 'EVR-TEST-1');
  });

  test('saves a clearly labelled local order when server is offline', () async {
    server.offline = true;
    final placed = await repository.placeOrder(sampleOrder());
    expect(placed.status, 'saved locally');
    final history = await repository.getOrders(userId: 7);
    expect(history.length, 1);
    expect(history.first.id, 'EVR-TEST-1');
    expect((await repository.getOrders(userId: 8)), isEmpty);
    expect((await repository.getOrderById('EVR-TEST-1')).status, 'saved locally');
  });

  test('order history is available after reopening app without server', () async {
    await repository.placeOrder(sampleOrder());
    server.offline = true;
    final reopened = OrderRepositoryImpl(
      dioClient: DioClient(
        preferenceService: preferences,
        dio: Dio(BaseOptions(baseUrl: 'http://localhost:3001'))
          ..interceptors.add(server),
      ),
      preferenceService: await PreferenceService.init(),
    );
    final history = await reopened.getOrders(userId: 7);
    expect(history.length, 1);
    expect(history.first.items.first.product.title, 'Test Product');
  });

  test('order history does not show other users orders', () async {
    await repository.placeOrder(sampleOrder(userId: 7));
    await repository.placeOrder(sampleOrder(id: 'EVR-TEST-2', userId: 8));
    final history = await repository.getOrders(userId: 7);
    expect(history.length, 1);
    expect(history.first.userId, 7);
  });
}
