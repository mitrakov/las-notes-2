import 'dart:collection';

class TrixStack<T> {
  final Queue<T> _stack = Queue();

  T push(T t) {
    _stack.add(t);
    return t;
  }

  T? pop() {
    if (_stack.isEmpty) return null;
    return _stack.removeLast();
  }

  T? peek()    => _stack.lastOrNull;
  void clear() => _stack.clear();
}
