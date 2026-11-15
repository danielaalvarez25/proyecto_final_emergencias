ExUnit.start()

defmodule PruebasPersonaB do
  use ExUnit.Case, async: false

  setup do
    dir = "tmp_pruebas_persona_b_#{System.unique_integer([:positive])}"
    Application.put_env(:emergencias, :data_dir, dir)

    on_exit(fn ->
      Application.delete_env(:emergencias, :data_dir)
      File.rm_rf(dir)
    end)

    start_supervised!(Recursos)
    start_supervised!(Necesidades)
    start_supervised!(Albergues)
    start_supervised!(Usuarios)
    start_supervised!(Zonas)
    start_supervised!(Personas)
    start_supervised!(Mascotas)
    :ok
  end

  test "registro automático, contraseña protegida y permisos por rol" do
    assert {:ok, usuario} = Usuarios.conectar("laura_test", "clave123", "ciudadano", "centro")
    assert usuario.conectado
    assert usuario.password == ""
    assert :ok = Usuarios.autorizar("laura_test", :report_person)
    assert {:error, :permiso_denegado} = Usuarios.autorizar("laura_test", :register_zone)
    assert {:error, :contrasena_incorrecta} = Usuarios.conectar("laura_test", "otra123")
    assert {:error, :contrasena_muy_corta} = Usuarios.conectar("nueva_test", "123")
    assert :ok = Usuarios.registrar_actividad("laura_test", :report_person, "Prueba")
    assert {:ok, usuario_guardado} = Usuarios.consultar("laura_test")
    assert [%{accion: "report_person", detalle: "Prueba"} | _] = usuario_guardado.actividad
  end

  test "estadísticas recursivas suman zona, sectores y puntos" do
    assert {:ok, _zona} = Zonas.registrar("zona_test", "Zona de prueba", :critico, 10)
    assert {:ok, _sector} = Zonas.agregar_sector("zona_test", "Sector 1", 5)
    assert {:ok, _punto} = Zonas.agregar_punto("zona_test", "Sector 1", "Punto A", 2)
    assert {:ok, _punto} = Zonas.agregar_punto("zona_test", "Sector 1", "Punto B", 3)

    assert {:ok,
            %{personas_estimadas: 20, sectores: 1, puntos_atencion: 2, nivel: :critico}} =
             Zonas.estadisticas("zona_test")
  end

  test "personas guardan historial y mensajes pueden marcarse entregados" do
    assert {:ok, persona} =
             Personas.registrar("persona_test", "doc_test", "Andrés", 25, "centro", :reportada)

    assert [%{estado: :reportada}] = persona.historial
    assert {:ok, _persona} = Personas.cambiar_estado("doc_test", :localizada)
    assert {:error, :transicion_invalida} = Personas.cambiar_estado("doc_test", :sin_informacion)

    assert {:ok, mensaje} = Personas.enviar_mensaje("doc_test", "Laura", "Estoy bien")
    assert mensaje.estado == :pendiente
    assert {:ok, mensaje_entregado} = Personas.marcar_mensaje(mensaje.id, :entregado)
    assert mensaje_entregado.estado == :entregado
    assert {:ok, [^mensaje_entregado]} = Personas.listar_mensajes("doc_test")
  end

  test "el ingreso al albergue también cambia el estado de la persona" do
    assert {:ok, _} = Albergues.registrar("shelter_test", "Albergue de prueba", "centro", 2)
    assert {:ok, _} = Personas.registrar("persona_shelter_test", "doc_shelter_test", "Andrés", nil, "centro", :reportada)

    assert {:ok, %{persona: %{estado: :en_albergue}}} =
             Personas.ingresar_albergue("shelter_test", "doc_shelter_test")

    assert {:ok, %{estado: :en_albergue}} = Personas.consultar("doc_shelter_test")
  end

  test "matching recursivo puntúa reportes y resuelve ambos al confirmar" do
    assert {:ok, perdida} =
             Mascotas.reportar(:perdida, "perro", "Luna", "collar rojo", "negra", "mediana", "centro", "555")

    assert {:ok, encontrada} =
             Mascotas.reportar(:encontrada, "perro", "desconocido", "collar rojo", "negra", "mediana", "centro", "556")

    assert {:ok, [{%Mascota{id: id_perdida}, %Mascota{id: id_encontrada}, 100}]} =
             Mascotas.buscar_coincidencias()

    assert id_perdida == perdida.id
    assert id_encontrada == encontrada.id
    assert {:ok, {%Mascota{estado: :resuelta}, %Mascota{estado: :resuelta}, 100}} =
             Mascotas.confirmar(perdida.id, encontrada.id)
  end

  test "CLI reconoce comandos, conserva argumentos entre comillas y rechaza vacíos" do
    assert {:ok, {:report_person, ["CC100", "Andrés Ruiz", "centro"]}} =
             CLI.parse("report_person CC100 \"Andrés Ruiz\" centro")

    assert {:error, :comando_vacio} = CLI.parse("   ")
    assert {:error, :comando_desconocido} = CLI.parse("hacer_algo")
  end

  test "flujo CLI registra a Laura, ubica a Andrés, compara mascotas y resume" do
    assert {:ok, _laura, "laura_cli_test"} =
             CLI.ejecutar("connect laura_cli_test clave123 coordinador centro Laura")

    assert {:ok, _zona, "laura_cli_test"} =
             CLI.ejecutar("register_zone centro_cli_test Centro critico", "laura_cli_test")

    assert {:ok, _persona, "laura_cli_test"} =
             CLI.ejecutar(
               "report_person CC_CLI_TEST \"Andrés Ruiz\" centro_cli_test reportada",
               "laura_cli_test"
             )

    assert {:ok, _albergue, "laura_cli_test"} =
             CLI.ejecutar(
               "register_shelter ALB_CLI_TEST \"Albergue Norte\" centro_cli_test 2",
               "laura_cli_test"
             )

    assert {:ok, %{persona: %{estado: :en_albergue}}, "laura_cli_test"} =
             CLI.ejecutar("register_entry ALB_CLI_TEST CC_CLI_TEST", "laura_cli_test")

    assert {:ok, _mensaje, "laura_cli_test"} =
             CLI.ejecutar(
               "send_family_message CC_CLI_TEST \"Estoy bien\"",
               "laura_cli_test"
             )

    assert {:ok, %{id: perdida}, "laura_cli_test"} =
             CLI.ejecutar(
               "report_pet lost perro Luna negra mediana centro_cli_test contacto1 \"collar rojo\"",
               "laura_cli_test"
             )

    assert {:ok, %{id: encontrada}, "laura_cli_test"} =
             CLI.ejecutar(
               "report_pet found perro desconocido negra mediana centro_cli_test contacto2 \"collar rojo\"",
               "laura_cli_test"
             )

    assert {:ok, [{_reporte_perdido, _reporte_encontrado, puntaje}], "laura_cli_test"} =
             CLI.ejecutar("match_pets", "laura_cli_test")

    assert puntaje == 100
    assert {:ok, {_perdida, _encontrada, 100}, "laura_cli_test"} =
             CLI.ejecutar("confirm_pet_match #{perdida} #{encontrada}", "laura_cli_test")

    assert {:ok, resumen, "laura_cli_test"} =
             CLI.ejecutar("summary", "laura_cli_test")

    assert resumen.usuarios_conectados == ["laura_cli_test"]
    assert [%Persona{documento: "CC_CLI_TEST", estado: :en_albergue}] = resumen.personas_localizadas
    assert length(resumen.mensajes) == 1
    assert Enum.count(resumen.mascotas, &(&1.estado == :resuelta)) == 2
  end
end
