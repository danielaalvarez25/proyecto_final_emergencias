defmodule Cupos do
  @moduledoc """
  Lógica pura de los albergues (sin procesos ni archivos).

  Trabaja sobre un mapa %{codigo => %Albergue{}} y nunca lo modifica:
  cada operación devuelve un mapa nuevo. El GenServer Albergues
  serializa el acceso y persiste.

  Reglas: la ocupación nunca supera la capacidad, una persona no puede
  estar en dos albergues a la vez y los códigos no se repiten. Los códigos
  se guardan en mayúsculas (a01 y A01 son el mismo albergue).
  """

  # Registro y consulta
  @doc """
  Registra un albergue. ocupacion es la ocupación inicial (personas ya
  alojadas sin documento registrado); por defecto 0.
  """
  def registrar(mapa, codigo, nombre, zona, capacidad, ocupacion \\ 0) do
    case normalizar_codigo(codigo) do
      {:error, razon} ->
        {:error, razon}

      {:ok, codigo} ->
        case validar_registro(mapa, codigo, nombre, zona, capacidad, ocupacion) do
          :ok ->
            albergue = %Albergue{
              codigo: codigo,
              nombre: String.trim(nombre),
              zona: String.trim(zona),
              capacidad: capacidad,
              ocupacion: ocupacion
            }

            {:ok, albergue, Map.put(mapa, codigo, albergue)}

          error ->
            error
        end
    end
  end

  # Devuelve :ok o el primer error encontrado, en este orden:
  # nombre, zona, capacidad, ocupación y código repetido
  defp validar_registro(mapa, codigo, nombre, zona, capacidad, ocupacion) do
    [
      validar_texto(nombre),
      validar_texto(zona),
      validar_capacidad(capacidad),
      validar_ocupacion(ocupacion, capacidad),
      validar_libre(mapa, codigo)
    ]
    |> Enum.find(:ok, fn resultado -> resultado != :ok end)
  end

  @doc "Busca un albergue por código (sin distinguir mayúsculas)."
  def obtener(mapa, codigo) do
    clave = codigo |> to_string() |> String.trim() |> String.upcase()

    case Map.fetch(mapa, clave) do
      {:ok, albergue} -> {:ok, albergue}
      :error -> {:error, :no_existe}
    end
  end

  @doc "Lista albergues ordenados por código. Filtro opcional: `zona: \"...\"."
  def listar(mapa, filtros \\ []) do
    mapa
    |> Map.values()
    |> Enum.filter(fn albergue ->
      Enum.all?(filtros, fn
        {:zona, valor} -> minusculas(albergue.zona) == minusculas(valor)
        _otro -> true
      end)
    end)
    |> Enum.sort_by(& &1.codigo)
  end

  @doc "Cupos libres de un albergue."
  def cupos(albergue), do: albergue.capacidad - albergue.ocupacion

  @doc "Porcentaje de ocupación (0.0 a 100.0). Un albergue sin capacidad cuenta como 0.0."
  def porcentaje(%{capacidad: 0}), do: 0.0
  def porcentaje(albergue), do: Float.round(albergue.ocupacion * 100 / albergue.capacidad, 1)

  @doc "Resumen listo para mostrar."
  def resumen(albergue) do
    %{
      codigo: albergue.codigo,
      nombre: albergue.nombre,
      zona: albergue.zona,
      capacidad: albergue.capacidad,
      ocupacion: albergue.ocupacion,
      cupos: cupos(albergue),
      porcentaje: porcentaje(albergue),
      recursos: albergue.recursos,
      necesidades: albergue.necesidades
    }
  end

  @doc "Los limite albergues con mayor porcentaje de ocupación (desempata por código)."
  def mayor_ocupacion(mapa, limite \\ 3) do
    mapa
    |> Map.values()
    |> Enum.sort_by(&{-porcentaje(&1), &1.codigo})
    |> Enum.take(limite)
  end

  @doc "Código del albergue donde está alojada la persona, o :ninguno."
  def donde_esta(mapa, documento), do: buscar(Map.values(mapa), to_string(documento) |> String.trim())

  # Recursiva sobre la lista de albergues.
  # Caso base: no quedan albergues, la persona no está alojada en ninguno
  defp buscar([], _documento), do: :ninguno

  # Caso recursivo: si el primer albergue la tiene se devuelve su código,
  # si no se sigue buscando en el resto
  defp buscar([albergue | resto], documento) do
    if Enum.member?(albergue.personas, documento) do
      {:ok, albergue.codigo}
    else
      buscar(resto, documento)
    end
  end

  #  Ingreso y salida
  @doc "Registra el ingreso de una persona. Nunca supera la capacidad."
  def ingresar(mapa, codigo, documento) do
    case obtener(mapa, codigo) do
      {:error, razon} ->
        {:error, razon}

      {:ok, albergue} ->
        case validar_documento(documento) do
          {:error, razon} ->
            {:error, razon}

          {:ok, documento} ->
            case validar_ingreso(mapa, albergue, documento) do
              :ok ->
                actualizado = %{
                  albergue
                  | ocupacion: albergue.ocupacion + 1,
                    personas: albergue.personas ++ [documento]
                }

                {:ok, actualizado, Map.put(mapa, actualizado.codigo, actualizado)}

              error ->
                error
            end
        end
    end
  end

  # La persona no debe estar alojada en ningún albergue y debe haber cupo
  defp validar_ingreso(mapa, albergue, documento) do
    case validar_no_alojada(mapa, albergue, documento) do
      :ok -> validar_cupo(albergue)
      error -> error
    end
  end

  @doc "Registra la salida de una persona alojada en ese albergue."
  def salir(mapa, codigo, documento) do
    case obtener(mapa, codigo) do
      {:error, razon} ->
        {:error, razon}

      {:ok, albergue} ->
        case validar_documento(documento) do
          {:error, razon} ->
            {:error, razon}

          {:ok, documento} ->
            case validar_alojada(albergue, documento) do
              :ok ->
                actualizado = %{
                  albergue
                  | ocupacion: albergue.ocupacion - 1,
                    personas: Enum.reject(albergue.personas, fn persona -> persona == documento end)
                }

                {:ok, actualizado, Map.put(mapa, actualizado.codigo, actualizado)}

              error ->
                error
            end
        end
    end
  end

  defp validar_no_alojada(mapa, albergue, documento) do
    case donde_esta(mapa, documento) do
      :ninguno -> :ok
      {:ok, codigo} when codigo == albergue.codigo -> {:error, :persona_ya_registrada}
      {:ok, _otro} -> {:error, :persona_en_otro_albergue}
    end
  end

  defp validar_alojada(albergue, documento) do
    if Enum.member?(albergue.personas, documento),
      do: :ok,
      else: {:error, :persona_no_registrada}
  end

  defp validar_cupo(albergue) do
    if cupos(albergue) > 0, do: :ok, else: {:error, :albergue_lleno}
  end

  #  Asociaciones

  @doc "Asocia un recurso (por código) al albergue."
  def asociar_recurso(mapa, codigo, recurso) do
    asociar(mapa, codigo, recurso, :recursos)
  end

  @doc "Asocia una necesidad (por id) al albergue."
  def asociar_necesidad(mapa, codigo, necesidad) do
    asociar(mapa, codigo, necesidad, :necesidades)
  end

  defp asociar(mapa, codigo, elemento, campo) do
    case obtener(mapa, codigo) do
      {:error, razon} ->
        {:error, razon}

      {:ok, albergue} ->
        case validar_texto(elemento) do
          :ok ->
            elemento = String.trim(elemento)

            if elemento in Map.fetch!(albergue, campo) do
              {:error, :ya_asociado}
            else
              actualizado = Map.update!(albergue, campo, &(&1 ++ [elemento]))
              {:ok, actualizado, Map.put(mapa, actualizado.codigo, actualizado)}
            end

          error ->
            error
        end
    end
  end

  #  Conversión a filas de texto

  @doc "Convierte un albergue en la fila que guarda Almacen."
  def a_fila(albergue) do
    [
      albergue.codigo,
      albergue.nombre,
      albergue.zona,
      albergue.capacidad,
      albergue.ocupacion,
      albergue.personas |> Enum.sort() |> Enum.join(";"),
      Enum.join(albergue.recursos, ";"),
      Enum.join(albergue.necesidades, ";")
    ]
  end

  @doc "Reconstruye un albergue desde su fila. Una fila dañada devuelve :error."
  def desde_fila([codigo, nombre, zona, capacidad, ocupacion, personas, recursos, necesidades]) do
    personas = personas |> String.split(";", trim: true) |> Enum.uniq()

    case Integer.parse(capacidad) do
      {c, ""} when c >= 0 ->
        case Integer.parse(ocupacion) do
          {o, ""} when o >= 0 and o <= c ->
            if o >= length(personas) do
              {:ok,
               %Albergue{
                 codigo: codigo,
                 nombre: nombre,
                 zona: zona,
                 capacidad: c,
                 ocupacion: o,
                 personas: personas,
                 recursos: String.split(recursos, ";", trim: true),
                 necesidades: String.split(necesidades, ";", trim: true)
               }}
            else
              :error
            end

          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  def desde_fila(_otra), do: :error

  #  Validaciones

  defp normalizar_codigo(codigo) when is_binary(codigo) do
    case String.trim(codigo) do
      "" -> {:error, :datos_invalidos}
      limpio -> {:ok, String.upcase(limpio)}
    end
  end

  defp normalizar_codigo(_otro), do: {:error, :datos_invalidos}

  defp validar_texto(texto) do
    if is_binary(texto) and String.trim(texto) != "", do: :ok, else: {:error, :datos_invalidos}
  end

  # El documento se guarda tal cual; se rechaza ";" porque separa los documentos en el archivo.
  defp validar_documento(documento) when is_binary(documento) or is_integer(documento) do
    limpio = documento |> to_string() |> String.trim()

    if limpio == "" or String.contains?(limpio, ";"),
      do: {:error, :documento_invalido},
      else: {:ok, limpio}
  end

  defp validar_documento(_otro), do: {:error, :documento_invalido}

  defp validar_capacidad(capacidad) when is_integer(capacidad) and capacidad >= 0, do: :ok
  defp validar_capacidad(_capacidad), do: {:error, :capacidad_invalida}

  defp validar_ocupacion(ocupacion, capacidad)
       when is_integer(ocupacion) and ocupacion >= 0 and ocupacion <= capacidad,
       do: :ok

  defp validar_ocupacion(_ocupacion, _capacidad), do: {:error, :ocupacion_invalida}

  defp validar_libre(mapa, codigo) do
    if Map.has_key?(mapa, codigo), do: {:error, :codigo_duplicado}, else: :ok
  end

  defp minusculas(texto), do: texto |> to_string() |> String.trim() |> String.downcase()
end
