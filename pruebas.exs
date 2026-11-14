# Ejecuta todas las pruebas del proyecto

ExUnit.start()

File.ls!()
|> Enum.filter(fn nombre ->
  String.starts_with?(nombre, "pruebas_") and String.ends_with?(nombre, ".exs")
end)
|> Enum.sort()
|> Enum.each(&Code.require_file/1)
