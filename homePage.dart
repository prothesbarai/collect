import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:provider/provider.dart';
import 'package:mycheck/provider/IncreDecreProvider.dart';
import '../otherpages/otherpage.dart';

class HomePage extends StatefulWidget {
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Box box1;
  late Box box2;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    openHiveBoxes();
  }

  Future<void> openHiveBoxes() async {
    try {
      box1 = await Hive.openBox('pp');
      box2 = await Hive.openBox('ss');

      if (box1.get('price1') == null) {
        await box1.put("name", 'Product Example');
        await box1.put('details', {'a': 'Apple', 'b': 'Ball'});
      }

      // Sync box2 price from box1
      await syncPriceFromBox1ToBox2();

      setState(() {
        isLoading = false;
      });
    } catch (e) {
      print("❌ Hive init error: $e");
    }
  }

  Future<void> syncPriceFromBox1ToBox2() async {
    var priceFromBox1 = box1.get('price1');
    await box2.put('price', priceFromBox1);
    if (box2.get('name') == null) {
      await box2.put('name', 'Customer Example');
      await box2.put('age', 25);
    }
  }

  Future<void> updatePrice() async {
    var priceFromBox1 = box1.get('price1'); // Get the previous price before update

    await box1.put("price1", 906505690); // Updated price
    await syncPriceFromBox1ToBox2(); // Sync to box2


    var updatedPrice = box1.get('price1');
    if(priceFromBox1 != updatedPrice){
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Previous Price: \$${priceFromBox1 ?? 'N/A'}  →  Updated Price: \$${updatedPrice ?? 'N/A'}",
            style: TextStyle(fontSize: 16),
          ),
          duration: Duration(seconds: 3), // Duration to show the SnackBar
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: Provider.of<IncreDecreProvider>(context, listen: false).Increement,
                  child: Text("+", style: TextStyle(fontSize: 20)),
                ),
                TextButton(
                  onPressed: Provider.of<IncreDecreProvider>(context, listen: false).Decrement,
                  child: Text("-", style: TextStyle(fontSize: 20)),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => Otherpage()),
                    );
                  },
                  child: Text('Go to Other Page'),
                ),
                TextButton(
                  onPressed: () async {
                    await updatePrice(); // Call to update and sync price
                  },
                  child: Text('Update Price'),
                ),
              ],
            ),

            // Product Info using ValueListenableBuilder
            Expanded(
              child: ValueListenableBuilder(
                valueListenable: box1.listenable(),
                builder: (context, Box box1Listen, _) {
                  final details = box1Listen.get('details', defaultValue: {}) as Map? ?? {};
                  return ValueListenableBuilder(
                    valueListenable: box2.listenable(),
                    builder: (context, Box box2Listen, _) {
                      return ListView(
                        children: [
                          Card(child: ListTile(title: Text("Product: ${box1Listen.get('name') ?? 'N/A'}"))),
                          Card(child: ListTile(title: Text("Price: \$${box2Listen.get('price') ?? '0'}"))),
                          Card(child: ListTile(title: Text("Customer: ${box2Listen.get('name') ?? 'N/A'}"))),
                          Card(child: ListTile(title: Text("Age: ${box2Listen.get('age') ?? 'N/A'}"))),
                          Card(child: ListTile(title: Text("Detail A: ${details['a'] ?? 'N/A'}"))),
                          Card(child: ListTile(title: Text("Detail B: ${details['b'] ?? 'N/A'}"))),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        backgroundColor: Colors.blueAccent,
        child: Text(
          Provider.of<IncreDecreProvider>(context).value.toStringAsFixed(0),
          style: TextStyle(color: Colors.white, fontSize: 20),
        ),
      ),
    );
  }
}
