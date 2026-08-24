import 'package:flutter/material.dart';

import '../data/camouflage_service.dart';

class CamouflageScreen extends StatefulWidget {
  const CamouflageScreen({super.key});

  @override
  State<CamouflageScreen> createState() => _CamouflageScreenState();
}

class _CamouflageScreenState extends State<CamouflageScreen> {
  String _display = '0';
  String _expression = '';
  double? _firstOperand;
  String? _operator;
  bool _shouldResetDisplay = false;

  final _pinDialogController = TextEditingController();

  @override
  void dispose() {
    _pinDialogController.dispose();
    super.dispose();
  }

  void _onDigitPress(String digit) {
    setState(() {
      if (_display == '0' || _shouldResetDisplay) {
        _display = digit;
        _shouldResetDisplay = false;
      } else if (_display.length < 12) {
        _display += digit;
      }
    });
  }

  void _onDecimalPress() {
    setState(() {
      if (_shouldResetDisplay) {
        _display = '0.';
        _shouldResetDisplay = false;
      } else if (!_display.contains('.')) {
        _display += '.';
      }
    });
  }

  void _onOperatorPress(String op) {
    setState(() {
      final currentVal = double.tryParse(_display) ?? 0;
      if (_firstOperand == null) {
        _firstOperand = currentVal;
      } else if (_operator != null && !_shouldResetDisplay) {
        _calculate();
      }
      _operator = op;
      _expression = '${_formatNumber(_firstOperand!)} $op';
      _shouldResetDisplay = true;
    });
  }

  void _onEqualsPress() {
    // 1. Verificar si lo escrito en pantalla coincide con el PIN secreto de desbloqueo
    final cleanDisplay =
        _display.replaceAll('.', '').replaceAll('-', '').trim();
    if (CamouflageService.instance.unlock(cleanDisplay) ||
        CamouflageService.instance.unlock(_display.trim())) {
      return;
    }

    // 2. Si no es el PIN, calcular matemáticamente como una calculadora real
    setState(() {
      if (_firstOperand != null && _operator != null) {
        final secondOperand = double.tryParse(_display) ?? 0;
        _expression =
            '${_formatNumber(_firstOperand!)} $_operator ${_formatNumber(secondOperand)} =';
        _calculate();
        _firstOperand = null;
        _operator = null;
        _shouldResetDisplay = true;
      }
    });
  }

  void _calculate() {
    if (_firstOperand == null || _operator == null) return;
    final secondOperand = double.tryParse(_display) ?? 0;
    double result = 0;

    switch (_operator) {
      case '+':
        result = _firstOperand! + secondOperand;
        break;
      case '−':
      case '-':
        result = _firstOperand! - secondOperand;
        break;
      case '×':
      case '*':
        result = _firstOperand! * secondOperand;
        break;
      case '÷':
      case '/':
        if (secondOperand == 0) {
          _display = 'Error';
          _firstOperand = null;
          _operator = null;
          return;
        }
        result = _firstOperand! / secondOperand;
        break;
    }

    _display = _formatNumber(result);
    _firstOperand = result;
  }

  String _formatNumber(double val) {
    if (val == val.roundToDouble()) {
      return val.toInt().toString();
    }
    return val
        .toStringAsFixed(4)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  void _onClear() {
    setState(() {
      _display = '0';
      _expression = '';
      _firstOperand = null;
      _operator = null;
      _shouldResetDisplay = false;
    });
  }

  void _onPlusMinus() {
    setState(() {
      if (_display != '0' && _display != 'Error') {
        if (_display.startsWith('-')) {
          _display = _display.substring(1);
        } else {
          _display = '-$_display';
        }
      }
    });
  }

  void _onPercent() {
    setState(() {
      final val = double.tryParse(_display) ?? 0;
      _display = _formatNumber(val / 100);
    });
  }

  void _showSecretUnlockDialog() {
    _pinDialogController.clear();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF22262B),
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: Colors.amberAccent, size: 20),
            SizedBox(width: 8),
            Text('PIN de Seguridad',
                style: TextStyle(fontSize: 16, color: Colors.white)),
          ],
        ),
        content: TextField(
          controller: _pinDialogController,
          autofocus: true,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 6,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Ingresa tu PIN secreto',
            hintStyle: TextStyle(color: Colors.white38),
            counterText: '',
            prefixIcon: Icon(Icons.lock_outline_rounded, color: Colors.white54),
          ),
          onSubmitted: (_) => _attemptDialogUnlock(ctx),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child:
                const Text('Cancelar', style: TextStyle(color: Colors.white60)),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: Colors.amber.shade700),
            onPressed: () => _attemptDialogUnlock(ctx),
            child: const Text('Desbloquear'),
          ),
        ],
      ),
    );
  }

  void _attemptDialogUnlock(BuildContext dialogContext) {
    final pin = _pinDialogController.text.trim();
    if (CamouflageService.instance.unlock(pin)) {
      Navigator.of(dialogContext).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PIN incorrecto.'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141414),
        elevation: 0,
        leading: const Icon(Icons.calculate_outlined, color: Colors.white54),
        title: GestureDetector(
          onLongPress: _showSecretUnlockDialog,
          child: const Text(
            'Calculadora',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 18,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Ajustes',
            icon: const Icon(Icons.history_rounded, color: Colors.white38),
            onPressed: _showSecretUnlockDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            children: [
              // Pantalla de la calculadora
              Expanded(
                flex: 3,
                child: Container(
                  width: double.infinity,
                  alignment: Alignment.bottomRight,
                  padding: const EdgeInsets.only(bottom: 24, right: 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (_expression.isNotEmpty)
                        Text(
                          _expression,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 20,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      const SizedBox(height: 8),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          _display,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 56,
                            fontWeight: FontWeight.w300,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 16),

              // Teclado numérico y de operaciones
              Expanded(
                flex: 7,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildRow(['AC', '+/-', '%', '÷'], isTopRow: true),
                    _buildRow(['7', '8', '9', '×']),
                    _buildRow(['4', '5', '6', '−']),
                    _buildRow(['1', '2', '3', '+']),
                    _buildRow(['0', '.', '='], hasDoubleZero: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(List<String> buttons,
      {bool isTopRow = false, bool hasDoubleZero = false}) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: buttons.map((label) {
          final isOperator = ['÷', '×', '−', '+', '='].contains(label);
          final isSpecial = ['AC', '+/-', '%'].contains(label);

          Color bgColor = const Color(0xFF242424);
          Color textColor = Colors.white;

          if (isOperator) {
            bgColor = Colors.amber.shade800;
            textColor = Colors.white;
          } else if (isSpecial) {
            bgColor = const Color(0xFF383838);
            textColor = Colors.white70;
          }

          final flex = (label == '0' && hasDoubleZero) ? 2 : 1;

          return Expanded(
            flex: flex,
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: SizedBox.expand(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: bgColor,
                    foregroundColor: textColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(32),
                    ),
                    elevation: 0,
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: () {
                    if (label == 'AC') {
                      _onClear();
                    } else if (label == '+/-') {
                      _onPlusMinus();
                    } else if (label == '%') {
                      _onPercent();
                    } else if (label == '=') {
                      _onEqualsPress();
                    } else if (['+', '−', '×', '÷'].contains(label)) {
                      _onOperatorPress(label);
                    } else if (label == '.') {
                      _onDecimalPress();
                    } else {
                      _onDigitPress(label);
                    }
                  },
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: isOperator ? 26 : 22,
                      fontWeight:
                          isOperator ? FontWeight.w500 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
