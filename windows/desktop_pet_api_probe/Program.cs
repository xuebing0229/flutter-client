using System.Reflection;
using VPet_Simulator.Core;

static void Dump(Type type)
{
    Console.WriteLine($"TYPE {type.FullName}");
    foreach (var ctor in type.GetConstructors(BindingFlags.Public | BindingFlags.Instance))
        Console.WriteLine("CTOR " + ctor);
    foreach (var method in type.GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly))
        Console.WriteLine("METHOD " + method);
}

Dump(typeof(GraphCore));
Dump(typeof(Picture));
Dump(typeof(GraphInfo));
Dump(typeof(GameSave));
