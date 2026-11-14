ExUnit.start()

defmodule PruebasAlmacen do
  use ExUnit.Case, async: false

  setup do
    dir = "tmp_pruebas_#{System.unique_integer([:positive])}"
    File.mkdir(dir)
    Application.put_env(:emergencias, :data_dir, dir)

    on_exit(fn ->
      Application.delete_env(:emergencias, :data_dir)
      File.rm_rf(dir)
    end)

    :ok
  end

  test "un archivo que no existe se lee como lista vacía" do
    assert {:ok, []} = Almacen.leer("no_existe.txt")
  end

  test "agregar y leer devuelve los mismos campos" do
    :ok = Almacen.agregar("recursos.txt", ["R001", "agua", 200, "litros", "centro_acopio_1"])
    :ok = Almacen.agregar("recursos.txt", ["R002", "arroz", 50, "kg", "albergue_2"])

    assert {:ok, filas} = Almacen.leer("recursos.txt")

    assert filas == [
             ["R001", "agua", "200", "litros", "centro_acopio_1"],
             ["R002", "arroz", "50", "kg", "albergue_2"]
           ]
  end

  test "los campos con |, barra invertida y saltos de línea sobreviven" do
    campos = ["N001", "agua | potable", "ruta\\sur", "línea 1\nlínea 2", ""]
    :ok = Almacen.agregar("necesidades.txt", campos)

    assert {:ok, [leido]} = Almacen.leer("necesidades.txt")
    assert leido == campos
  end

  test "codificar y decodificar son inversas" do
    campos = ["a", "b|c", "\\", "x\ny", "", "ñandú"]

    assert campos |> Almacen.codificar_linea() |> Almacen.decodificar_linea() == campos
  end

  test "reescribir reemplaza todo el contenido" do
    :ok = Almacen.agregar("albergues.txt", ["A01", "Norte", 150])
    :ok = Almacen.agregar("albergues.txt", ["A02", "Sur", 80])

    :ok = Almacen.reescribir("albergues.txt", [["A02", "Sur", 90]])

    assert {:ok, [["A02", "Sur", "90"]]} = Almacen.leer("albergues.txt")
  end

  test "escrituras concurrentes no pierden ni mezclan registros" do
    total = 200

    1..total
    |> Task.async_stream(
      fn i -> Almacen.agregar("concurrente.txt", ["id#{i}", "valor|#{i}"]) end,
      max_concurrency: 50
    )
    |> Enum.each(fn {:ok, resultado} -> assert resultado == :ok end)

    assert {:ok, filas} = Almacen.leer("concurrente.txt")
    assert length(filas) == total
    assert Enum.all?(filas, fn [id, valor] -> valor == "valor|" <> String.trim_leading(id, "id") end)
    assert filas |> Enum.map(&hd/1) |> Enum.uniq() |> length() == total
  end
end
