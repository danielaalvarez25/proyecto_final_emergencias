defmodule Almacen do
  @moduledoc """
  Persistencia genérica en archivos de texto plano.

  Cada registro es una línea con campos separados por |
  (campo|campo|campo). Los caracteres especiales se escapan:

    * \\ se guarda como \\\\
    * \  se guarda como \\|
    * salto de línea se guarda como \\n

  El directorio se configura con
  Application.put_env(:emergencias, :data_dir, "ruta") y por defecto
  es data/. Los archivos son nombre relativos a ese directorio,
  por ejemplo "recursos.txt".

  Devuelve :ok / {:ok, filas} / {:error, razon}; nunca lanza
  excepciones por situaciones esperadas.
  """

  @doc "Directorio donde se guardan los archivos."
  def directorio do
    Application.get_env(:emergencias, :data_dir, "data")
  end

  @doc "Ruta completa de un archivo de datos."
  def ruta(nombre), do: directorio() <> "/" <> nombre

  @doc """
  Agrega un registro al final del archivo.

  Cada campo se convierte con to_string/1. Una sola escritura en modo
  :append por registro, así que varios procesos pueden agregar a la
  vez sin mezclar líneas.
  """
  def agregar(nombre, campos) when is_binary(nombre) and is_list(campos) do
    crear_directorio()
    File.write(ruta(nombre), codificar_linea(campos) <> "\n", [:append])
  end

  @doc """
  Lee todos los registros. Un archivo que aún no existe es una lista vacía.
  """
  def leer(nombre) when is_binary(nombre) do
    case File.read(ruta(nombre)) do
      {:ok, contenido} ->
        filas =
          contenido
          |> String.split("\n", trim: true)
          |> Enum.map(&decodificar_linea/1)

        {:ok, filas}

      {:error, :enoent} ->
        {:ok, []}

      {:error, razon} ->
        {:error, razon}
    end
  end

  @doc """
  Reemplaza todo el contenido del archivo con las filas dadas.

  Cada fila queda en su propia línea. Una lista vacía deja el archivo vacío.
  """
  def reescribir(nombre, filas) when is_binary(nombre) and is_list(filas) do
    contenido =
      filas
      |> Enum.map(fn campos -> codificar_linea(campos) <> "\n" end)
      |> Enum.join()

    crear_directorio()
    File.write(ruta(nombre), contenido)
  end

  # Crea la carpeta de datos. Si ya existe, File.mkdir/1 devuelve error y
  # no pasa nada: si la carpeta no se puede crear, el error aparece al escribir.
  defp crear_directorio do
    File.mkdir(directorio())
  end

  #  Codificación

  @doc "Convierte una lista de campos en una línea de texto (sin salto final)."
  def codificar_linea(campos) do
    campos
    |> Enum.map(&escapar/1)
    |> Enum.join("|")
  end

  @doc """
  Convierte una línea de texto en la lista de campos original.

  Es recursiva sobre la lista de caracteres de la línea: consume uno o dos
  por vez y acumula el campo actual y los campos ya terminados.
  """
  def decodificar_linea(linea), do: decodificar(String.codepoints(linea), "", [])

  defp escapar(campo) do
    campo
    |> to_string()
    |> String.replace("\\", "\\\\")
    |> String.replace("|", "\\|")
    |> String.replace("\n", "\\n")
  end

  # Caso base: fin de la línea, el campo en curso es el último.
  defp decodificar([], actual, acumulados), do: Enum.reverse([actual | acumulados])

  # Caso recursivo: se mira el primer carácter (o los dos primeros si hay escape).
  defp decodificar(["\\", "\\" | resto], actual, acumulados),
    do: decodificar(resto, actual <> "\\", acumulados)

  defp decodificar(["\\", "|" | resto], actual, acumulados),
    do: decodificar(resto, actual <> "|", acumulados)

  defp decodificar(["\\", "n" | resto], actual, acumulados),
    do: decodificar(resto, actual <> "\n", acumulados)

  # Un | sin escapar cierra el campo actual.
  defp decodificar(["|" | resto], actual, acumulados),
    do: decodificar(resto, "", [actual | acumulados])

  defp decodificar([caracter | resto], actual, acumulados),
    do: decodificar(resto, actual <> caracter, acumulados)
end
