import 'package:flutter_test/flutter_test.dart';
import 'package:top_tailers_/models/product.dart';
import 'package:top_tailers_/providers/cart_provider.dart';

const _shirt = Product(
  id: 'a',
  productName: 'Shirt',
  description: 'Test shirt',
  price: 100,
  category: 'Readymade',
  availability: true,
);

const _soldOut = Product(
  id: 'b',
  productName: 'Velvet',
  description: 'Sold out',
  price: 500,
  category: 'Fabrics',
  availability: false,
);

void main() {
  test('adds products and computes totals', () {
    final cart = CartProvider();
    expect(cart.isEmpty, isTrue);

    cart.add(_shirt);
    cart.add(_shirt, quantity: 2);

    expect(cart.count, 3);
    expect(cart.total, 300);
    expect(cart.quantityOf('a'), 3);
  });

  test('refuses unavailable products', () {
    final cart = CartProvider();
    expect(cart.add(_soldOut), isFalse);
    expect(cart.isEmpty, isTrue);
  });

  test('setting quantity below one removes the item', () {
    final cart = CartProvider();
    cart.add(_shirt);
    cart.setQuantity('a', 0);
    expect(cart.isEmpty, isTrue);
  });

  test('quantity is capped', () {
    final cart = CartProvider();
    cart.add(_shirt, quantity: 500);
    expect(cart.quantityOf('a'), CartProvider.maxQuantity);
  });

  test('clear empties the cart', () {
    final cart = CartProvider();
    cart.add(_shirt);
    cart.clear();
    expect(cart.isEmpty, isTrue);
    expect(cart.total, 0);
  });
}
