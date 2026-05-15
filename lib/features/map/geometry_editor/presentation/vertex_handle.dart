import 'package:flutter/material.dart';

class VertexHandle extends StatelessWidget {
  const VertexHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Center(
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF3182CE), width: 2),
            boxShadow: const [
              BoxShadow(blurRadius: 3, color: Color(0x66000000)),
            ],
          ),
        ),
      ),
    );
  }
}
