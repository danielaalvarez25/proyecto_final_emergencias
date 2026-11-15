defmodule CLI do
  @commands ~w(
    connect disconnect register_zone register_sector register_point
    report_person find_person send_family_message list_family_messages
    report_pet list_pet_reports match_pets confirm_pet_match
    register_resource list_resources transfer_resource
    register_need list_needs assign_resource
    register_shelter check_shelter register_entry register_exit
    critical_resources pending_needs summary
  )

  @mensajes_error %{
    usuario_no_existe: "El usuario no existe.",
    usuario_no_conectado: "Primero debes conectarte.",
    permiso_denegado: "Tu tipo de usuario no tiene permiso para esa acción.",
    contrasena_incorrecta: "La contraseña no coincide.",
    contrasena_muy_corta: "La contraseña debe tener al menos cuatro caracteres.",
    cantidad_invalida: "La cantidad debe ser un entero positivo.",
    stock_insuficiente: "No hay suficiente inventario disponible.",
    albergue_lleno: "El albergue no tiene cupos disponibles.",
    persona_no_existe: "No se encontró esa persona.",
    zona_no_existe: "No se encontró esa zona.",
    tipo_reporte_invalido: "El tipo debe ser perdida o encontrada.",
    umbral_invalido: "El puntaje debe estar entre 0 y 100.",
    reporte_no_existe: "No se encontró uno de los reportes.",
    reporte_ya_resuelto: "Uno de los reportes ya fue resuelto.",
    puntaje_insuficiente: "El puntaje de coincidencia no alcanza el mínimo.",
    comando_desconocido: "No reconozco ese comando.",
    argumentos_invalidos: "Revisa los argumentos del comando."
  }

  def parse(linea) when is_binary(linea) do
    case tokenizar(String.trim(linea)) do
      [] ->
        {:error, :comando_vacio}

      [comando | argumentos] ->
        if comando in @commands do
          {:ok, {String.to_atom(comando), argumentos}}
        else
          {:error, :comando_desconocido}
        end
    end
  end

  def parse(_), do: {:error, :comando_invalido}

  def ejecutar(linea, usuario_actual \\ nil) do
    with {:ok, {comando, argumentos}} <- parse(linea),
         {:ok, resultado, nuevo_usuario} <-
           despachar(comando, argumentos, usuario_actual) do
      {:ok, resultado, nuevo_usuario}
    end
  end

  def iniciar do
    case Process.whereis(Sistema) do
      nil ->
        case Sistema.iniciar() do
          {:ok, _pid} -> bucle(nil)
          {:error, razon} -> {:error, razon}
        end

      _pid ->
        bucle(nil)
    end
  end

  defp despachar(:connect, [usuario, contrasena | opciones], _actual) do
    tipo = Enum.at(opciones, 0, "ciudadano")
    zona = Enum.at(opciones, 1, "sin_zona")
    nombre = Enum.at(opciones, 2, "")

    case Usuarios.conectar(usuario, contrasena, tipo, zona, nombre) do
      {:ok, usuario_conectado} ->
        {:ok, usuario_conectado, usuario_conectado.username}

      error ->
        error
    end
  end

  defp despachar(:disconnect, _argumentos, nil) do
    {:error, :usuario_no_conectado}
  end

  defp despachar(:disconnect, _argumentos, usuario) do
    case Usuarios.desconectar(usuario) do
      {:ok, resultado} -> {:ok, resultado, nil}
      error -> error
    end
  end

  defp despachar(_comando, _argumentos, nil) do
    {:error, :usuario_no_conectado}
  end

  defp despachar(comando, argumentos, usuario) do
    with :ok <- Usuarios.autorizar(usuario, comando),
         {:ok, resultado} <- ejecutar_autorizado(comando, argumentos, usuario) do
         _ = Usuarios.registrar_actividad(usuario, comando, "Comando ejecutado")
      {:ok, resultado, usuario}
    end
  end

  defp ejecutar_autorizado(:register_zone, [codigo, nombre, nivel], _usuario) do
    Zonas.registrar(codigo, nombre, nivel)
  end

  defp ejecutar_autorizado(
         :register_zone,
         [codigo, nombre, nivel, personas],
         _usuario
       ) do
    with {:ok, cantidad} <- entero(personas) do
      Zonas.registrar(codigo, nombre, nivel, cantidad)
    end
  end

  defp ejecutar_autorizado(:register_sector, [zona, nombre], _usuario) do
    Zonas.agregar_sector(zona, nombre)
  end

  defp ejecutar_autorizado(
         :register_sector,
         [zona, nombre, personas],
         _usuario
       ) do
    with {:ok, cantidad} <- entero(personas) do
      Zonas.agregar_sector(zona, nombre, cantidad)
    end
  end

  defp ejecutar_autorizado(:register_point, [zona, sector, punto], _usuario) do
    Zonas.agregar_punto(zona, sector, punto)
  end

  defp ejecutar_autorizado(
         :register_point,
         [zona, sector, punto, personas],
         _usuario
       ) do
    with {:ok, cantidad} <- entero(personas) do
      Zonas.agregar_punto(zona, sector, punto, cantidad)
    end
  end

  defp ejecutar_autorizado(
         :report_person,
         [documento, nombre, zona],
         _usuario
       ) do
    Personas.registrar(
      documento,
      documento,
      nombre,
      nil,
      zona,
      :reportada
    )
  end

  defp ejecutar_autorizado(
         :report_person,
         [documento, nombre, zona, estado],
         _usuario
       ) do
    Personas.registrar(
      documento,
      documento,
      nombre,
      nil,
      zona,
      estado
    )
  end

  defp ejecutar_autorizado(:find_person, [documento], _usuario) do
    Personas.buscar(documento: documento)
  end

  defp ejecutar_autorizado(:find_person, [campo, valor], _usuario) do
    case campo do
      campo when campo in ["nombre", "name"] ->
        Personas.buscar(nombre: valor)

      campo when campo in ["zona", "zone"] ->
        Personas.buscar(zona: valor)

      campo when campo in ["estado", "status"] ->
        Personas.buscar(estado: valor)

      campo when campo in ["documento", "id"] ->
        Personas.buscar(documento: valor)

      _ ->
        {:error, :filtro_invalido}
    end
  end

  defp ejecutar_autorizado(
         :send_family_message,
         [documento, contenido],
         usuario
       ) do
    Personas.enviar_mensaje(documento, usuario, contenido)
  end

  defp ejecutar_autorizado(
         :list_family_messages,
         [documento],
         _usuario
       ) do
    Personas.listar_mensajes(documento)
  end

  defp ejecutar_autorizado(
         :report_pet,
         [tipo, especie, nombre, color, tamano, zona, contacto],
         _usuario
       ) do
    Mascotas.reportar(tipo, especie, nombre, "", color, tamano, zona, contacto)
  end

  defp ejecutar_autorizado(
         :report_pet,
         [tipo, especie, nombre, color, tamano, zona, contacto, caracteristicas],
         _usuario
       ) do
    Mascotas.reportar(
      tipo,
      especie,
      nombre,
      caracteristicas,
      color,
      tamano,
      zona,
      contacto
    )
  end

  defp ejecutar_autorizado(:list_pet_reports, [], _usuario) do
    Mascotas.listar()
  end

  defp ejecutar_autorizado(
         :list_pet_reports,
         [campo, valor],
         _usuario
       ) do
    case campo do
      campo when campo in ["especie", "species"] ->
        Mascotas.listar(especie: valor)

      campo when campo in ["zona", "zone"] ->
        Mascotas.listar(zona: valor)

      campo when campo in ["estado", "status"] ->
        Mascotas.listar(estado: valor)

      _ ->
        {:error, :filtro_invalido}
    end
  end

  defp ejecutar_autorizado(:match_pets, [], _usuario) do
    Mascotas.buscar_coincidencias()
  end

  defp ejecutar_autorizado(:match_pets, [umbral], _usuario) do
    with {:ok, cantidad} <- entero(umbral) do
      Mascotas.buscar_coincidencias(cantidad)
    end
  end

  defp ejecutar_autorizado(
         :confirm_pet_match,
         [perdida, encontrada],
         _usuario
       ) do
    Mascotas.confirmar(perdida, encontrada)
  end

  defp ejecutar_autorizado(
         :register_resource,
         [codigo, nombre, cantidad, unidad, ubicacion],
         _usuario
       ) do
    with {:ok, numero} <- entero(cantidad) do
      Recursos.registrar(
        codigo,
        nombre,
        "general",
        numero,
        unidad,
        ubicacion
      )
    end
  end

  defp ejecutar_autorizado(
         :register_resource,
         [codigo, nombre, categoria, cantidad, unidad, ubicacion],
         _usuario
       ) do
    with {:ok, numero} <- entero(cantidad) do
      Recursos.registrar(
        codigo,
        nombre,
        categoria,
        numero,
        unidad,
        ubicacion
      )
    end
  end

  defp ejecutar_autorizado(:list_resources, argumentos, _usuario) do
    with {:ok, filtros} <-
           filtros(argumentos, [:nombre, :ubicacion, :categoria]) do
      Recursos.listar(filtros)
    end
  end

  defp ejecutar_autorizado(
         :transfer_resource,
         [codigo, origen, destino, cantidad],
         _usuario
       ) do
    with {:ok, numero} <- entero(cantidad) do
      Recursos.transferir(codigo, origen, destino, numero)
    end
  end

  defp ejecutar_autorizado(
         :register_need,
         [tipo, cantidad, prioridad, zona | descripcion],
         usuario
       ) do
    with {:ok, numero} <- entero(cantidad) do
      Necesidades.registrar(
        tipo,
        numero,
        prioridad,
        zona,
        Enum.join(descripcion, " "),
        usuario
      )
    end
  end

  defp ejecutar_autorizado(:list_needs, argumentos, _usuario) do
    with {:ok, filtros} <-
           filtros(argumentos, [:zona, :tipo, :prioridad, :estado]) do
      Necesidades.listar(filtros)
    end
  end

  defp ejecutar_autorizado(
         :assign_resource,
         [id, recurso, cantidad],
         _usuario
       ) do
    with {:ok, numero} <- entero(cantidad) do
      Despacho.asignar(id, recurso, numero)
    end
  end

  defp ejecutar_autorizado(
         :register_shelter,
         [codigo, nombre, zona, capacidad],
         _usuario
       ) do
    with {:ok, cupos} <- entero(capacidad) do
      Albergues.registrar(codigo, nombre, zona, cupos)
    end
  end

  defp ejecutar_autorizado(
         :register_shelter,
         [codigo, nombre, zona, capacidad, ocupacion],
         _usuario
       ) do
    with {:ok, cupos} <- entero(capacidad),
         {:ok, ocupacion} <- entero(ocupacion) do
      Albergues.registrar(codigo, nombre, zona, cupos, ocupacion)
    end
  end

  defp ejecutar_autorizado(:check_shelter, [codigo], _usuario) do
    with {:ok, albergue} <- Albergues.consultar(codigo) do
      {:ok, Cupos.resumen(albergue)}
    end
  end

  defp ejecutar_autorizado(
         :register_entry,
         [codigo, documento],
         _usuario
       ) do
    Personas.ingresar_albergue(codigo, documento)
  end

  defp ejecutar_autorizado(
         :register_exit,
         [codigo, documento],
         _usuario
       ) do
    Personas.salir_albergue(codigo, documento)
  end

  defp ejecutar_autorizado(:critical_resources, [], _usuario) do
    Recursos.criticos()
  end

  defp ejecutar_autorizado(:critical_resources, [umbral], _usuario) do
    with {:ok, numero} <- entero(umbral) do
      Recursos.criticos(numero)
    end
  end

  defp ejecutar_autorizado(:pending_needs, [], _usuario) do
    Necesidades.pendientes()
  end

  defp ejecutar_autorizado(:summary, [], _usuario) do
    Resumen.generar()
  end

  defp ejecutar_autorizado(_comando, _argumentos, _usuario) do
    {:error, :argumentos_invalidos}
  end

  defp entero(texto) do
    case Integer.parse(texto) do
      {numero, ""} -> {:ok, numero}
      _ -> {:error, :numero_entero_invalido}
    end
  end

  defp filtros(argumentos, permitidos) do
    Enum.reduce_while(argumentos, {:ok, []}, fn argumento, {:ok, acumulados} ->
      case String.split(argumento, "=", parts: 2) do
        [campo, valor] ->
          case Enum.find(permitidos, &(Atom.to_string(&1) == campo)) do
            nil -> {:halt, {:error, :filtro_invalido}}
            atom -> {:cont, {:ok, [{atom, valor} | acumulados]}}
          end

        _ ->
          {:halt, {:error, :filtro_invalido}}
      end
    end)
    |> case do
      {:ok, resultado} -> {:ok, Enum.reverse(resultado)}
      error -> error
    end
  end

  defp bucle(usuario) do
    case IO.gets("emergencias> ") do
      nil ->
        :ok

      linea ->
        linea = String.trim(linea)

        if linea in ["salir", "exit"] do
          :ok
        else
          case ejecutar(linea, usuario) do
            {:ok, resultado, nuevo_usuario} ->
              IO.inspect(resultado, pretty: true, limit: :infinity)
              bucle(nuevo_usuario)

            {:error, razon} ->
              mensaje = Map.get(@mensajes_error, razon, inspect(razon))
              IO.puts("Error: #{mensaje}")
              bucle(usuario)
          end
        end
    end
  end

  defp tokenizar(linea) do
    Regex.scan(~r/"(?:\\.|[^"])*"|'(?:\\.|[^'])*'|\S+/, linea, capture: :first)
    |> Enum.map(&hd/1)
    |> Enum.map(fn token ->
      if String.starts_with?(token, ["\"", "'"]) do
        binary_part(token, 1, byte_size(token) - 2)
      else
        token
      end
    end)
  end
end
