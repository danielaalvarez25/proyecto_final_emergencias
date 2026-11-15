defmodule Usuarios do
  use GenServer
  require Logger

  @archivo "usuarios.txt"
  @archivo_actividad "actividad_usuarios.txt"

  @roles [:ciudadano, :voluntario, :coordinador, :administrador]

  @permisos %{
    ciudadano: [
      :disconnect,
      :report_person,
      :find_person,
      :send_family_message,
      :list_family_messages,
      :report_pet,
      :list_pet_reports,
      :match_pets,
      :summary
    ],
    voluntario: [
      :disconnect,
      :report_person,
      :find_person,
      :send_family_message,
      :list_family_messages,
      :report_pet,
      :list_pet_reports,
      :match_pets,
      :register_entry,
      :register_exit,
      :summary
    ],
    coordinador: [
      :confirm_pet_match,
      :list_needs,
      :list_resources,
      :transfer_resource,
      :check_shelter,
      :disconnect,
      :register_zone,
      :register_sector,
      :register_point,
      :report_person,
      :find_person,
      :send_family_message,
      :list_family_messages,
      :report_pet,
      :list_pet_reports,
      :match_pets,
      :register_need,
      :assign_resource,
      :register_resource,
      :register_shelter,
      :register_entry,
      :register_exit,
      :critical_resources,
      :pending_needs,
      :summary

    ],
    administrador: :all
  }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: Keyword.get(opts, :name, __MODULE__))
  end

  def conectar(username, password, tipo \\ :ciudadano, zona \\ "sin_zona", nombre \\ "", servidor \\ __MODULE__) do
    GenServer.call(servidor, {:conectar, username, password, tipo, zona, nombre})
  end

  def desconectar(username, servidor \\ __MODULE__) do
    GenServer.call(servidor, {:desconectar, username})
  end

  def consultar(username, servidor \\ __MODULE__) do
    GenServer.call(servidor, {:consultar, username})
  end

  def listar(servidor \\ __MODULE__) do
    GenServer.call(servidor, :listar)
  end

  def autorizar(username, accion, servidor \\ __MODULE__) do
    GenServer.call(servidor, {:autorizar, username, accion})
  end

  def registrar_actividad(username, accion, detalle \\ "", servidor \\ __MODULE__) do
    GenServer.call(servidor, {:registrar_actividad, username, accion, detalle})
  end

  @impl true
  def init(:ok) do
    {:ok, cargar_estado()}
  end

  @impl true
  def handle_call({:conectar, username, password, tipo, zona, nombre}, _from, estado) do
    with {:ok, username, password} <- validar_credenciales(username, password),
         {:ok, usuario} <- obtener_o_registrar(estado, username, password, tipo, zona, nombre) do
      usuario = %{usuario | conectado: true}
      estado = put_in(estado.usuarios[username], usuario)
      estado = registrar_evento(estado, username, :connect, "Inicio de sesión")
      guardar_usuarios(estado.usuarios)

      {:reply, {:ok, usuario_publico(usuario)}, estado}
    else
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  def handle_call({:desconectar, username}, _from, estado) do
    case Map.fetch(estado.usuarios, username) do
      {:ok, usuario} ->
        usuario = %{usuario | conectado: false}
        estado = put_in(estado.usuarios[username], usuario)
        estado = registrar_evento(estado, username, :disconnect, "Cierre de sesión")
        guardar_usuarios(estado.usuarios)

        {:reply, {:ok, usuario_publico(usuario)}, estado}

      :error ->
        {:reply, {:error, :usuario_no_existe}, estado}
    end
  end

  def handle_call({:consultar, username}, _from, estado) do
    respuesta =
      case Map.fetch(estado.usuarios, username) do
        {:ok, usuario} -> {:ok, usuario_publico(usuario)}
        :error -> {:error, :usuario_no_existe}
      end

    {:reply, respuesta, estado}
  end

  def handle_call(:listar, _from, estado) do
    usuarios =
      estado.usuarios
      |> Map.values()
      |> Enum.map(&usuario_publico/1)
      |> Enum.sort_by(& &1.username)

    {:reply, {:ok, usuarios}, estado}
  end

  def handle_call({:autorizar, username, accion}, _from, estado) do
    respuesta =
      case Map.fetch(estado.usuarios, username) do
        {:ok, %{conectado: true, tipo: tipo}} ->
          permisos = Map.get(@permisos, tipo, [])

          if permisos == :all or accion in permisos do
            :ok
          else
            {:error, :permiso_denegado}
          end

        {:ok, _usuario} ->
          {:error, :usuario_no_conectado}

        :error ->
          {:error, :usuario_no_existe}
      end

    {:reply, respuesta, estado}
  end

  def handle_call({:registrar_actividad, username, accion, detalle}, _from, estado) do
    case Map.fetch(estado.usuarios, username) do
      {:ok, %{conectado: true}} ->
        estado = registrar_evento(estado, username, accion, detalle)
        {:reply, :ok, estado}

      {:ok, _usuario} ->
        {:reply, {:error, :usuario_no_conectado}, estado}

      :error ->
        {:reply, {:error, :usuario_no_existe}, estado}
    end
  end

  defp validar_credenciales(username, password)
       when is_binary(username) and is_binary(password) do
    username = String.trim(username)

    cond do
      username == "" ->
        {:error, :usuario_invalido}

      byte_size(password) < 4 ->
        {:error, :contrasena_muy_corta}

      true ->
        {:ok, username, password}
    end
  end

  defp validar_credenciales(_username, _password) do
    {:error, :datos_invalidos}
  end

  defp obtener_o_registrar(estado, username, password, tipo, zona, nombre) do
    case Map.fetch(estado.usuarios, username) do
      {:ok, usuario} ->
        if verificar_contrasena(password, usuario.password) do
          {:ok, usuario}
        else
          {:error, :contrasena_incorrecta}
        end

      :error ->
        with {:ok, tipo} <- convertir_rol(tipo),
             :ok <- validar_rol_publico(tipo),
             true <- is_binary(zona) and String.trim(zona) != "",
             nombre <- if(nombre == "", do: username, else: nombre),
             true <- is_binary(nombre) and String.trim(nombre) != "" do
          usuario =
            Usuario.crear(
              username,
              hash_contrasena(password),
              tipo,
              String.trim(zona),
              String.trim(nombre)
            )

          {:ok, usuario}
        else
          {:error, razon} -> {:error, razon}
          false -> {:error, :datos_invalidos}
        end
    end
  end

  defp convertir_rol(tipo) when tipo in @roles, do: {:ok, tipo}

  defp convertir_rol(tipo) when is_binary(tipo) do
    case String.downcase(String.trim(tipo)) do
      "ciudadano" -> {:ok, :ciudadano}
      "voluntario" -> {:ok, :voluntario}
      "coordinador" -> {:ok, :coordinador}
      "administrador" -> {:ok, :administrador}
      _ -> {:error, :tipo_usuario_invalido}
    end
  end

  defp convertir_rol(_tipo), do: {:error, :tipo_usuario_invalido}

  defp validar_rol_publico(:administrador) do
    {:error, :administrador_no_autoregistrable}
  end

  defp validar_rol_publico(_tipo), do: :ok

  defp registrar_evento(estado, username, accion, detalle) do
    fecha = DateTime.utc_now() |> DateTime.to_iso8601()

    evento = %{
      accion: to_string(accion),
      detalle: to_string(detalle),
      fecha: fecha
    }

    usuario = Map.fetch!(estado.usuarios, username)
    usuario = %{usuario | actividad: [evento | usuario.actividad]}
    estado = put_in(estado.usuarios[username], usuario)

    case Almacen.agregar(@archivo_actividad, [
           username,
           evento.accion,
           evento.detalle,
           evento.fecha
         ]) do
      :ok -> :ok
      {:error, razon} -> Logger.error("No se guardó la actividad del usuario: #{inspect(razon)}")
    end

    estado
  end

  defp cargar_estado do
    usuarios =
      case Almacen.leer(@archivo) do
        {:ok, filas} ->
          filas
          |> Enum.flat_map(&usuario_desde_fila/1)
          |> Map.new(fn usuario -> {usuario.username, usuario} end)

        {:error, razon} ->
          Logger.error("No se pudieron leer los usuarios: #{inspect(razon)}")
          %{}
      end

    %{usuarios: cargar_actividad(usuarios)}
  end

  defp usuario_desde_fila([username, password, nombre, tipo, zona]) do
    with {:ok, tipo} <- convertir_rol(tipo) do
      [Usuario.crear(username, password, tipo, zona, nombre)]
    else
      _ -> []
    end
  end

  defp usuario_desde_fila(_fila), do: []

  defp cargar_actividad(usuarios) do
    case Almacen.leer(@archivo_actividad) do
      {:ok, filas} ->
        Enum.reduce(filas, usuarios, fn
          [username, accion, detalle, fecha], acumulado ->
            case Map.fetch(acumulado, username) do
              {:ok, usuario} ->
                evento = %{accion: accion, detalle: detalle, fecha: fecha}
                Map.put(acumulado, username, %{usuario | actividad: [evento | usuario.actividad]})

              :error ->
                acumulado
            end

          _fila, acumulado ->
            acumulado
        end)

      {:error, razon} ->
        Logger.error("No se pudo leer la actividad: #{inspect(razon)}")
        usuarios
    end
  end

  defp guardar_usuarios(usuarios) do
    filas =
      usuarios
      |> Map.values()
      |> Enum.sort_by(& &1.username)
      |> Enum.map(fn usuario ->
        [
          usuario.username,
          usuario.password,
          usuario.nombre,
          usuario.tipo,
          usuario.zona
        ]
      end)

    case Almacen.reescribir(@archivo, filas) do
      :ok -> :ok
      {:error, razon} -> Logger.error("No se pudieron guardar los usuarios: #{inspect(razon)}")
    end
  end

  defp hash_contrasena(password) do
    Application.ensure_all_started(:crypto)
    salt = :crypto.strong_rand_bytes(16)
    hash = :crypto.pbkdf2_hmac(:sha256, password, salt, 100_000, 32)

    Base.encode16(salt, case: :lower) <>
      "$" <>
      Base.encode16(hash, case: :lower)
  end

  defp verificar_contrasena(password, almacenada) do
    case String.split(almacenada, "$", parts: 2) do
      [salt_hex, hash_hex] ->
        with {:ok, salt} <- Base.decode16(salt_hex, case: :mixed),
             {:ok, esperado} <- Base.decode16(hash_hex, case: :mixed) do
          actual = :crypto.pbkdf2_hmac(:sha256, password, salt, 100_000, 32)
          comparar_en_tiempo_constante(actual, esperado)
        else
          _ -> false
        end

      _ ->
        false
    end
  end

  defp comparar_en_tiempo_constante(a, b) when byte_size(a) == byte_size(b) do
    a
    |> :binary.bin_to_list()
    |> Enum.zip(:binary.bin_to_list(b))
    |> Enum.reduce(0, fn {x, y}, acc ->
      Bitwise.bor(acc, Bitwise.bxor(x, y))
    end)
    |> then(&(&1 == 0))
  end

  defp comparar_en_tiempo_constante(_a, _b), do: false

  defp usuario_publico(usuario) do
    %{usuario | password: ""}
  end
end
