defmodule Personas do
  use GenServer
  require Logger

  @archivo_personas "personas.txt"
  @archivo_historial "historial_personas.txt"
  @archivo_mensajes "mensajes_familiares.txt"

  @estados [
    :sin_informacion,
    :reportada,
    :localizada,
    :trasladada,
    :en_albergue,
    :reunificada
  ]

  @transiciones %{
    sin_informacion: [:reportada, :localizada],
    reportada: [:localizada, :trasladada, :en_albergue],
    localizada: [:trasladada, :en_albergue, :reunificada],
    trasladada: [:localizada, :en_albergue, :reunificada],
    en_albergue: [:localizada, :trasladada, :reunificada],
    reunificada: []
  }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: Keyword.get(opts, :name, __MODULE__))
  end

  def registrar(id, documento, nombre, edad, zona, estado \\ :sin_informacion, servidor \\ __MODULE__) do
    GenServer.call(servidor, {:registrar, id, documento, nombre, edad, zona, estado})
  end

  def consultar(documento, servidor \\ __MODULE__) do
    GenServer.call(servidor, {:consultar, documento})
  end

  def buscar(filtros \\ [], servidor \\ __MODULE__) do
    GenServer.call(servidor, {:buscar, filtros})
  end

  def cambiar_estado(documento, estado, servidor \\ __MODULE__) do
    GenServer.call(servidor, {:cambiar_estado, documento, estado})
  end

  def ingresar_albergue(codigo_albergue, documento, servidor \\ __MODULE__) do
    GenServer.call(servidor, {:ingresar_albergue, codigo_albergue, documento})
  end

  def salir_albergue(codigo_albergue, documento, servidor \\ __MODULE__) do
    GenServer.call(servidor, {:salir_albergue, codigo_albergue, documento})
  end

  def enviar_mensaje(destinatario, remitente, contenido, servidor \\ __MODULE__) do
    GenServer.call(servidor, {:enviar_mensaje, destinatario, remitente, contenido})
  end

  def listar_mensajes(destinatario, servidor \\ __MODULE__) do
    GenServer.call(servidor, {:listar_mensajes, destinatario})
  end

  def marcar_mensaje(id, estado, servidor \\ __MODULE__) do
    GenServer.call(servidor, {:marcar_mensaje, id, estado})
  end

  @impl true
  def init(:ok) do
    personas = cargar_personas()
    personas = cargar_historial(personas)
    mensajes = cargar_mensajes()

    {:ok,
     %{
       personas: personas,
       mensajes: mensajes,
       siguiente_mensaje: siguiente_id_mensaje(mensajes)
     }}
  end

  @impl true
  def handle_call({:registrar, id, documento, nombre, edad, zona, estado}, _from, datos) do
    with {:ok, estado} <- convertir_estado(estado),
         :ok <- validar_persona(datos.personas, id, documento, nombre, edad, zona, estado) do
      persona = Persona.crear(id, documento, nombre, edad, zona, estado)
      persona = agregar_evento(persona, estado)

      personas = Map.put(datos.personas, id, persona)
      guardar_personas(personas)
      guardar_historial(personas)

      {:reply, {:ok, persona}, %{datos | personas: personas}}
    else
      {:error, razon} -> {:reply, {:error, razon}, datos}
    end
  end

  def handle_call({:consultar, documento}, _from, datos) do
    respuesta =
      case buscar_por_documento(datos.personas, documento) do
        nil -> {:error, :persona_no_existe}
        persona -> {:ok, persona}
      end

    {:reply, respuesta, datos}
  end

  def handle_call({:buscar, filtros}, _from, datos) do
    resultado =
      datos.personas
      |> Map.values()
      |> Enum.filter(&coincide_filtros?(&1, filtros))
      |> Enum.sort_by(& &1.documento)

    {:reply, {:ok, resultado}, datos}
  end

  def handle_call({:cambiar_estado, documento, nuevo_estado}, _from, datos) do
    with {:ok, nuevo_estado} <- convertir_estado(nuevo_estado),
         %Persona{} = persona <- buscar_por_documento(datos.personas, documento),
         true <- nuevo_estado in Map.fetch!(@transiciones, persona.estado) do
      persona = actualizar_estado(persona, nuevo_estado)
      personas = Map.put(datos.personas, persona.id, persona)
      guardar_personas(personas)
      guardar_historial(personas)

      {:reply, {:ok, persona}, %{datos | personas: personas}}
    else
      nil -> {:reply, {:error, :persona_no_existe}, datos}
      false -> {:reply, {:error, :transicion_invalida}, datos}
      {:error, razon} -> {:reply, {:error, razon}, datos}
    end
  end

  def handle_call({:ingresar_albergue, codigo, documento}, _from, datos) do
    case buscar_por_documento(datos.personas, documento) do
      nil ->
        {:reply, {:error, :persona_no_existe}, datos}

      persona ->
        if :en_albergue in Map.fetch!(@transiciones, persona.estado) do
          case Albergues.ingresar(codigo, documento) do
            {:ok, albergue} ->
              persona = actualizar_estado(persona, :en_albergue)
              personas = Map.put(datos.personas, persona.id, persona)
              guardar_personas(personas)
              guardar_historial(personas)

              {:reply, {:ok, %{persona: persona, albergue: albergue}},
               %{datos | personas: personas}}

            {:error, razon} ->
              {:reply, {:error, razon}, datos}
          end
        else
          {:reply, {:error, :transicion_invalida}, datos}
        end
    end
  end

  def handle_call({:salir_albergue, codigo, documento}, _from, datos) do
    case buscar_por_documento(datos.personas, documento) do
      nil ->
        {:reply, {:error, :persona_no_existe}, datos}

      persona ->
        case Albergues.salir(codigo, documento) do
          {:ok, albergue} ->
            persona =
              if :trasladada in Map.fetch!(@transiciones, persona.estado) do
                actualizar_estado(persona, :trasladada)
              else
                persona
              end

            personas = Map.put(datos.personas, persona.id, persona)
            guardar_personas(personas)
            guardar_historial(personas)

            {:reply, {:ok, %{persona: persona, albergue: albergue}},
             %{datos | personas: personas}}

          {:error, razon} ->
            {:reply, {:error, razon}, datos}
        end
    end
  end

  def handle_call({:enviar_mensaje, destinatario, remitente, contenido}, _from, datos) do
    if buscar_por_documento(datos.personas, destinatario) == nil do
      {:reply, {:error, :persona_no_existe}, datos}
    else
      if is_binary(contenido) and String.trim(contenido) != "" do
        id =
          "M" <>
            String.pad_leading(
              Integer.to_string(datos.siguiente_mensaje),
              3,
              "0"
            )

        fecha = DateTime.utc_now() |> DateTime.to_iso8601()
        mensaje = Mensaje.crear(id, fecha, remitente, destinatario, contenido)

        mensajes = Map.put(datos.mensajes, id, mensaje)
        guardar_mensajes(mensajes)

        {:reply, {:ok, mensaje},
         %{datos | mensajes: mensajes, siguiente_mensaje: datos.siguiente_mensaje + 1}}
      else
        {:reply, {:error, :mensaje_vacio}, datos}
      end
    end
  end

  def handle_call({:listar_mensajes, destinatario}, _from, datos) do
    mensajes =
      datos.mensajes
      |> Map.values()
      |> Enum.filter(&(&1.destinatario == to_string(destinatario)))
      |> Enum.sort_by(& &1.id)

    {:reply, {:ok, mensajes}, datos}
  end

  def handle_call({:marcar_mensaje, id, estado}, _from, datos)
      when estado in [:pendiente, :entregado] do
    case Map.fetch(datos.mensajes, id) do
      {:ok, mensaje} ->
        mensaje = %{mensaje | estado: estado}
        mensajes = Map.put(datos.mensajes, id, mensaje)
        guardar_mensajes(mensajes)

        {:reply, {:ok, mensaje}, %{datos | mensajes: mensajes}}

      :error ->
        {:reply, {:error, :mensaje_no_existe}, datos}
    end
  end

  def handle_call({:marcar_mensaje, _id, _estado}, _from, datos) do
    {:reply, {:error, :estado_mensaje_invalido}, datos}
  end

  defp validar_persona(personas, id, documento, nombre, edad, zona, estado) do
    cond do
      not texto_valido?(id) -> {:error, :id_invalido}
      not texto_valido?(documento) -> {:error, :documento_invalido}
      not texto_valido?(nombre) -> {:error, :nombre_invalido}
      not texto_valido?(zona) -> {:error, :zona_invalida}
      edad != nil and (not is_integer(edad) or edad < 0) -> {:error, :edad_invalida}
      not estado_valido?(estado) -> {:error, :estado_invalido}
      Map.has_key?(personas, id) -> {:error, :id_duplicado}
      Enum.any?(personas, fn {_id, p} -> p.documento == to_string(documento) end) ->
        {:error, :documento_duplicado}
      true -> :ok
    end
  end

  defp actualizar_estado(persona, estado) do
    evento = %{estado: estado, fecha: DateTime.utc_now() |> DateTime.to_iso8601()}
    %{persona | estado: estado, historial: [evento | persona.historial]}
  end

  defp agregar_evento(persona, estado) do
    evento = %{estado: estado, fecha: DateTime.utc_now() |> DateTime.to_iso8601()}
    %{persona | historial: [evento | persona.historial]}
  end

  defp buscar_por_documento(personas, documento) do
    documento = to_string(documento)
    Enum.find_value(personas, fn {_id, persona} ->
      if persona.documento == documento, do: persona
    end)
  end

  defp coincide_filtros?(persona, filtros) do
    Enum.all?(filtros, fn
      {:documento, valor} -> persona.documento == to_string(valor)
      {:nombre, valor} ->
        String.contains?(String.downcase(persona.nombre), String.downcase(to_string(valor)))
      {:zona, valor} -> String.downcase(persona.zona) == String.downcase(to_string(valor))
      {:estado, valor} ->
        case convertir_estado(valor) do
          {:ok, estado} -> persona.estado == estado
          _ -> false
        end
      _ -> true
    end)
  end

  defp convertir_estado(estado) when estado in @estados, do: {:ok, estado}

  defp convertir_estado(estado) when is_binary(estado) do
    estado =
      estado
      |> String.trim()
      |> String.downcase()
      |> String.replace(" ", "_")

    case Enum.find(@estados, &(Atom.to_string(&1) == estado)) do
      nil -> {:error, :estado_invalido}
      atom -> {:ok, atom}
    end
  end

  defp convertir_estado(_estado), do: {:error, :estado_invalido}

  defp estado_valido?(estado), do: estado in @estados

  defp texto_valido?(texto) do
    is_binary(texto) and String.trim(texto) != ""
  end

  defp guardar_personas(personas) do
    filas =
      personas
      |> Map.values()
      |> Enum.sort_by(& &1.id)
      |> Enum.map(fn persona ->
        [
          persona.id,
          persona.documento,
          persona.nombre,
          persona.edad || "",
          persona.zona,
          persona.estado
        ]
      end)

    guardar_archivo(@archivo_personas, filas)
  end

  defp guardar_historial(personas) do
    filas =
      personas
      |> Map.values()
      |> Enum.flat_map(fn persona ->
        Enum.map(persona.historial, fn evento ->
          [persona.id, evento.estado, evento.fecha]
        end)
      end)

    guardar_archivo(@archivo_historial, filas)
  end

  defp guardar_mensajes(mensajes) do
    filas =
      mensajes
      |> Map.values()
      |> Enum.sort_by(& &1.id)
      |> Enum.map(fn mensaje ->
        [
          mensaje.id,
          mensaje.fecha,
          mensaje.remitente,
          mensaje.destinatario,
          mensaje.contenido,
          mensaje.estado
        ]
      end)

    guardar_archivo(@archivo_mensajes, filas)
  end

  defp guardar_archivo(archivo, filas) do
    case Almacen.reescribir(archivo, filas) do
      :ok -> :ok
      {:error, razon} -> Logger.error("No se pudo guardar #{archivo}: #{inspect(razon)}")
    end
  end

  defp cargar_personas do
    case Almacen.leer(@archivo_personas) do
      {:ok, filas} ->
        filas
        |> Enum.flat_map(&persona_desde_fila/1)
        |> Map.new(fn persona -> {persona.id, persona} end)

      {:error, razon} ->
        Logger.error("No se pudieron leer las personas: #{inspect(razon)}")
        %{}
    end
  end

  defp persona_desde_fila([id, documento, nombre, edad, zona, estado]) do
    with {:ok, estado} <- convertir_estado(estado),
         {:ok, edad} <- convertir_edad(edad) do
      [Persona.crear(id, documento, nombre, edad, zona, estado)]
    else
      _ -> []
    end
  end

  defp persona_desde_fila(_fila), do: []

  defp convertir_edad(""), do: {:ok, nil}

  defp convertir_edad(edad) do
    case Integer.parse(edad) do
      {numero, ""} when numero >= 0 -> {:ok, numero}
      _ -> {:error, :edad_invalida}
    end
  end

  defp cargar_historial(personas) do
    case Almacen.leer(@archivo_historial) do
      {:ok, filas} ->
        Enum.reduce(filas, personas, fn
          [id, estado, fecha], acumulado ->
            case Map.fetch(acumulado, id) do
              {:ok, persona} ->
                evento = %{estado: estado, fecha: fecha}
                Map.put(acumulado, id, %{persona | historial: [evento | persona.historial]})

              :error ->
                acumulado
            end

          _fila, acumulado ->
            acumulado
        end)

      {:error, _razon} ->
        personas
    end
  end

  defp cargar_mensajes do
    case Almacen.leer(@archivo_mensajes) do
      {:ok, filas} ->
        filas
        |> Enum.flat_map(&mensaje_desde_fila/1)
        |> Map.new(fn mensaje -> {mensaje.id, mensaje} end)

      {:error, razon} ->
        Logger.error("No se pudieron leer los mensajes: #{inspect(razon)}")
        %{}
    end
  end

  defp mensaje_desde_fila([id, fecha, remitente, destinatario, contenido, estado]) do
    estado =
      case estado do
        "entregado" -> :entregado
        _ -> :pendiente
      end

    [Mensaje.crear(id, fecha, remitente, destinatario, contenido, estado)]
  end

  defp mensaje_desde_fila(_fila), do: []

  defp siguiente_id_mensaje(mensajes) do
    maximo =
      mensajes
      |> Map.keys()
      |> Enum.map(fn
        "M" <> resto ->
          case Integer.parse(resto) do
            {numero, ""} -> numero
            _ -> 0
          end

        _ ->
          0
      end)
      |> Enum.max(fn -> 0 end)

    maximo + 1
  end
end
