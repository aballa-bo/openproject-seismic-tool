# frozen_string_literal: true

module SeismicTool
  # Declarative description of the GL-AeDES 01/2014 form ("Scheda di valutazione
  # di danno e agibilità post-sisma per edifici a struttura prefabbricata o di
  # grande luce", Gruppo di Lavoro - Decreto Capo Dipartimento Rep. 827/2012).
  #
  # Every section is a list of blocks:
  #   { type: :fields, fields: [...] }   -> labelled inputs
  #   { type: :table, rows: [...], columns: [...] } -> grid of checkboxes/selects
  # Values are stored flat in AedesForm#data under the keys built here, so the
  # form renderer, the print view and the prefill all share this single source.
  module AedesSchema
    module_function

    def opts(*pairs) = pairs.map { |p| p.is_a?(Array) ? p : [p, p] }

    LEVELS = [["", "—"], ["lt13", "< 1/3"], ["13_23", "1/3 – 2/3"], ["gt23", "> 2/3"]].freeze
    YESNO = [["", "—"], ["si", "SI"], ["no", "NO"]].freeze
    MATERIALS = [["1", "C.A. prefabbricato"], ["2", "C.A. in opera"], ["3", "Muratura"], ["4", "Acciaio"],
                 ["5", "Legno"], ["6", "Misto acciaio-cls"], ["7", "Altro"]].freeze
    PI = [["nessuno", "Nessuno"], ["riparazioni", "Riparazioni"], ["puntellature", "Puntellature"],
          ["legature", "Legature"], ["demolizioni", "Demolizioni"], ["barriere", "Barriere di protezione"]].freeze

    def sections
      @sections ||= [s1, s2a, s2b, s3a, s3b, s3c, s3d, s4, s5, s6, s7, s8, s9].freeze
    end

    def section(id) = sections.find { |s| s[:id] == id }

    def label = "GL-AeDES 01/2014 (prefabbricati / grande luce)"

    def description
      "Scheda di valutazione di danno e agibilità post-sisma per edifici a struttura prefabbricata o di grande luce " \
        "(GL-AeDES 01/2014). La compilazione non costituisce verifica sismica; il giudizio finale resta al rilevatore."
    end

    def summary_key = "s9_analisi"

    def computed(_data) = {}

    # All keys that may be stored (used to whitelist submitted params).
    def keys
      @keys ||= sections.flat_map do |s|
        s[:blocks].flat_map do |b|
          if b[:type] == :fields
            b[:fields].map { |f| f[:key] }
          else
            b[:rows].flat_map { |r| b[:columns].map { |c| "#{b[:key]}_#{r[0]}_#{c[:key]}" } }
          end
        end
      end.freeze
    end

    # Human readable value of a field/column spec (for the print view).
    def display(spec, value)
      return "" if value.blank?

      case spec[:type]
      when :select
        (spec[:options].to_a.find { |k, _| k == value } || [nil, value])[1].to_s
      when :multi
        Array(value).map { |v| (spec[:options].to_a.find { |k, _| k == v } || [nil, v])[1] }.join(", ")
      when :bool, :check
        value.to_s.in?(%w[1 true si]) ? "SI" : ""
      else
        value.to_s
      end
    end

    def field(key)
      sections.each do |s|
        s[:blocks].each { |b| (b[:fields] || []).each { |f| return f if f[:key] == key } }
      end
      nil
    end

    # ---- helpers -----------------------------------------------------------
    def f(key, label, type = :text, options: nil, hint: nil, wide: false)
      { key: key, label: label, type: type, options: options, hint: hint, wide: wide }
    end

    def check_cols(list) = list.map { |k, l| { key: k, label: l, type: :check } }

    def table(key, rows, columns, title: nil)
      { type: :table, key: key, title: title, rows: rows, columns: columns }
    end

    # ---- sections ----------------------------------------------------------
    def s1
      { id: "s1", title: "Sezione 1 – Identificazione edificio", blocks: [
        { type: :fields, fields: [
          f("s1_provincia", "Provincia"), f("s1_comune", "Comune"), f("s1_frazione", "Frazione / Località"),
          f("s1_istat_provincia", "Codice ISTAT provincia"), f("s1_istat_comune", "Codice ISTAT comune"),
          f("s1_via_tipo", "Tipo di strada", :select,
            options: [["", "—"], ["1", "Via"], ["2", "Corso"], ["3", "Vicolo"], ["4", "Piazza"], ["5", "Altro"]]),
          f("s1_via", "Denominazione strada"), f("s1_civico", "Numero/i civico/i"),
          f("s1_coord_tipo", "Coordinate", :select,
            options: [["", "—"], ["utm", "Piane UTM (m)"], ["geo", "Geografiche (°)"], ["altro", "Altro"]]),
          f("s1_fuso", "Fuso (32-33-34)"),
          f("s1_datum", "Datum", :select, options: [["", "—"], ["ED50", "ED50"], ["WGS84", "WGS84"]]),
          f("s1_lat", "Lat./Nord"), f("s1_lon", "Long./Est"),
          f("s1_aggregato", "N° aggregato"), f("s1_edificio", "N° edificio"),
          f("s1_catasto", "Dati catastali – particelle", :text),
          f("s1_posizione", "Posizione edificio", :select,
            options: [["", "—"], ["1", "Isolato"], ["2", "Interno"], ["3", "D'estremità"], ["4", "D'angolo"]]),
          f("s1_denominazione", "Denominazione edificio o proprietario", :text, wide: true),
          f("s1_classe_uso", "Classe d'uso", :select,
            options: [["", "—"], ["1", "Classe I"], ["2", "Classe II"], ["3", "Classe III"], ["4", "Classe IV"]]),
          f("s1_codice_uso", "Codice uso"),
          f("s1_squadra", "Squadra"), f("s1_scheda_n", "Scheda n."), f("s1_scheda_tot", "di"),
          f("s1_data", "Data sopralluogo", :date),
          f("s1_schema", "Rappresentazione schematica dell'edificio e dei blocchi aggiunti", :textarea, wide: true)
        ] }
      ] }
    end

    def s2a
      { id: "s2a", title: "Sezione 2A – Descrizione edificio", blocks: [
        { type: :fields, fields: [
          f("s2a_piani", "N° piani totali (con interrati)", :number),
          f("s2a_altezza", "Altezza media di piano (m)", :number),
          f("s2a_superficie", "Superficie media di piano (m²)", :number),
          f("s2a_interrati", "Piani interrati", :select,
            options: [["", "—"], ["0", "0"], ["1", "1"], ["2", "2"], ["3", "≥ 3"]]),
          f("s2a_altezza_pilastri", "Altezza massima libera pilastri (m)", :number),
          f("s2a_eta", "Età di costruzione e ristrutturazione (max 4)", :multi,
            options: [["1", "≤ 1950"], ["2", "1951–61"], ["3", "1962–71"], ["4", "1972–75"], ["5", "1976–81"],
                      ["6", "1982–86"], ["7", "1987–91"], ["8", "1992–96"], ["9", "1997–2001"],
                      ["10", "2002–08"], ["11", "2009–11"], ["12", "> 2011"]]),
          f("s2a_uso", "Uso", :multi,
            options: [["A", "Residenziale"], ["B", "Produttivo"], ["C", "Commercio"], ["D", "Uffici"],
                      ["E", "Servizi pubblici"], ["F", "Deposito"], ["G", "Strategico"],
                      ["H", "Turistico-ricettivo"], ["I", "Parcheggio"], ["J", "Attività sportive"],
                      ["K", "Spazi espositivi"]]),
          f("s2a_unita", "Numero unità d'uso", :number),
          f("s2a_utilizzazione", "Utilizzazione", :select,
            options: [["", "—"], ["A", "> 65%"], ["B", "30–65%"], ["C", "< 30%"], ["D", "Non utilizzato"],
                      ["E", "In costruzione"], ["F", "Non finito"], ["G", "Abbandonato"]]),
          f("s2a_occupanti", "Occupanti ordinari", :number),
          f("s2a_occupanti_max", "Numero massimo occupanti", :number),
          f("s2a_proprieta", "Proprietà", :select, options: [["", "—"], ["A", "Pubblica"], ["B", "Privata"]])
        ] }
      ] }
    end

    def s2b
      blocks = %w[A B C D E]
      cols = blocks.map { |b| { key: b, label: "Blocco #{b}", type: :check } }
      rows = [["interna", "Posizione: interna"], ["esterna", "Posizione: esterna"]] +
             MATERIALS.map { |k, l| ["mat#{k}", "Materiale: #{l}"] } +
             [["solidale", "Connessione: solidale"], ["affiancato", "Connessione: affiancato"]]
      { id: "s2b", title: "Sezione 2B – Presenza di blocchi aggiunti alla struttura principale", blocks: [
        { type: :fields, fields: [f("s2b_assenti", "Blocchi aggiunti assenti", :bool)] },
        table("s2b", rows, cols),
        { type: :fields, fields: [
          f("s2b_note", "Per ogni blocco: n° piani, altezza (m), superficie media (m²), funzione, ID scheda AeDES", :textarea, wide: true)
        ] }
      ] }
    end

    def s3a
      cols = [{ key: "vert", label: "Elem. verticali", type: :check },
              { key: "orizz", label: "Elem. orizz. interm.", type: :check },
              { key: "cop", label: "Copertura", type: :check }]
      rows = MATERIALS.map { |k, l| [k, l] }
      { id: "s3a", title: "Sezione 3A – Tipologia dell'edificio", blocks: [
        table("s3a", rows, cols, title: "Materiale"),
        { type: :fields, fields: [
          f("s3a_fondazione", "Tipologia di fondazione", :multi,
            options: [["1", "Non identificata"], ["2", "Plinti isolati"], ["3", "Plinti collegati"],
                      ["4", "Travi rovesce"], ["5", "Platea"]]),
          f("s3a_fondazione_modo", "Modalità di approfondimento (fondazione)", :select,
            options: [["", "—"], ["A", "Non identificata"], ["B", "Presunta"], ["C", "Da interviste"],
                      ["D", "Da elaborati"], ["E", "Ispezione diretta"]]),
          f("s3a_sismo", "Sistema sismo-resistente", :multi,
            options: [["A", "Non identificato"], ["B", "Pilastri senza sistema controventante"],
                      ["C", "Pilastri con sistema controventante"], ["D", "Pareti portanti"],
                      ["E", "Celle tridimensionali"]]),
          f("s3a_impalcato", "Impalcato intermedio", :select,
            options: [["", "—"], ["1", "Assente"], ["2", "Non identificato"], ["3", "Deformabile nel proprio piano"],
                      ["4", "Rigido nel proprio piano"]])
        ] }
      ] }
    end

    def s3b
      cols = [%w[A Orizz.\ cost.], %w[B Orizz.\ var.], %w[C Inclinati\ cost.], %w[D Inclinati\ var.],
              %w[E Non\ identif.], %w[F A\ solaio\ piano], %w[G A\ solaio\ inclinato], %w[H Tegoli\ affianc.],
              %w[I Tegoli\ distanz.], %w[J Elementi\ leggeri], %w[K Presenza\ catene], %w[L Spingenti]]
      rows = [["1", "Non identificati"], ["2", "Membratura piena"], ["3", "Cassonetto o scatolare"],
              ["4", "Reticolari"], ["5", "Altro"]]
      { id: "s3b", title: "Sezione 3B – Copertura", blocks: [
        { type: :fields, fields: [
          f("s3b_luce", "Luce max > 10 m", :select, options: YESNO),
          f("s3b_ordini", "N° ordini copertura", :number),
          f("s3b_controventi", "Presenza controventi di falda", :select, options: YESNO),
          f("s3b_deform", "Caratteristiche deformative", :select,
            options: [["", "—"], ["ni", "Non identificata"], ["def", "Deformabile"], ["rig", "Rigida"]])
        ] },
        table("s3b", rows, cols.map { |k, l| { key: k, label: l, type: :check } })
      ] }
    end

    def s3c
      plan = ["Pianta compatta e simmetrica", "Rapporto lato maggiore/minore < 4",
              "Rientranze in pianta ≤ 5% dell'area", "Tamponatura esterna uniformemente e simmetricamente distribuita",
              "Assenza di nuclei o blocchi eccentrici", "Disposizione simmetrica di setti o controventi"]
      elev = ["Sistemi resistenti estesi a tutta l'altezza, assenza di sfalsamenti",
              "Tamponatura uniforme in altezza, assenza di finestre a nastro",
              "Massa uniforme tra i livelli (variazione ≤ 50%)",
              "Rientri sezioni orizzontali ≤ 10% rispetto all'orizzontamento sottostante",
              "Rientro di ogni orizzontamento ≤ 30% del primo"]
      { id: "s3c", title: "Sezione 3C – Regolarità", blocks: [
        { type: :fields, fields:
          plan.each_with_index.map { |l, i| f("s3c_p#{i + 1}", "In pianta: #{l}", :select, options: YESNO) } +
          elev.each_with_index.map { |l, i| f("s3c_e#{i + 1}", "In elevazione: #{l}", :select, options: YESNO) } }
      ] }
    end

    def s3d
      conn = [["1", "Pilastro/parete – fondazione"], ["2", "Trave – pilastro/parete"], ["3", "Impalcato – trave"],
              ["4", "Copertura – trave / pilastro"], ["5", "Pilastro/parete – pilastro/parete"],
              ["6", "Pannello – struttura"]]
      { id: "s3d", title: "Sezione 3D – Connessioni, pannelli, carichi speciali, elementi non strutturali", blocks: [
        table("s3d", conn, [{ key: "tipo", label: "Tipologia (cerniera, incastro, appoggio…)", type: :text },
                            { key: "modo", label: "Approfondimento", type: :select,
                              options: [["", "—"], ["A", "Non identificata"], ["B", "Presunta"], ["C", "Da interviste"],
                                        ["D", "Da elaborati"], ["E", "Ispezione diretta"]] }],
              title: "Connessioni"),
        { type: :fields, fields: [
          f("s3d_pannelli", "Pannelli di tamponatura", :multi,
            options: [["1", "Assenti"], ["2", "Prefabbr. orizz. appesi esterni"], ["3", "Prefabbr. orizz. appesi interni"],
                      ["4", "Prefabbr. orizz. infilati"], ["5", "Prefabbr. vert. con chiave di taglio"],
                      ["6", "Prefabbr. vert. senza chiave di taglio"], ["7", "Prefabbr. vert. infilati"],
                      ["8", "Prefabbricati impilati"], ["9", "C.A. gettati in opera"], ["10", "Muratura"],
                      ["11", "Sandwich"], ["12", "Lamiere grecate"], ["13", "Pareti stratificate a secco"],
                      ["14", "A base di legno"], ["15", "Altro"]]),
          f("s3d_carichi", "Carichi speciali", :multi,
            options: [["1", "Carroponte"], ["2", "Gru a sbalzo"], ["3", "Soppalchi caricati"],
                      ["4", "Scaffalature vincolate"], ["5", "Scaffalature non vincolate"],
                      ["6", "Macchinari su impalcati/copertura"], ["7", "Altro"]]),
          f("s3d_nonstrutt", "Altri elementi non strutturali", :multi,
            options: [["1", "Serbatoi"], ["2", "Tubazioni"], ["3", "Silos"], ["4", "Materiali pericolosi"],
                      ["5", "Passerelle di collegamento impianti"], ["6", "Altro"]])
        ] }
      ] }
    end

    def s4
      rows = [["1", "Pilastri"], ["2", "Travi"], ["3", "Pareti portanti"], ["4", "Controventi"], ["5", "Impalcati"],
              ["6", "Scale"], ["7", "Copertura"], ["8", "Danno pre-esistente (elementi)"],
              ["9", "Connessione pilastro/parete – fondazione"], ["10", "Connessione trave – pilastro/parete"],
              ["11", "Connessione impalcato – trave"], ["12", "Connessione copertura – trave/pilastro"],
              ["13", "Connessione pilastro/parete – pilastro/parete"], ["14", "Connessione pannello – struttura"],
              ["15", "Danno pre-esistente (connessioni)"]] +
             %w[A B C D E].each_with_index.map { |b, i| [(16 + i).to_s, "Danno complessivo del blocco aggiunto #{b}"] }
      cols = [{ key: "nullo", label: "Nullo", type: :check },
              { key: "d45", label: "D4–D5 Gravissimo", type: :select, options: LEVELS },
              { key: "d23", label: "D2–D3 Medio grave", type: :select, options: LEVELS },
              { key: "d1", label: "D1 Leggero", type: :select, options: LEVELS },
              { key: "pi", label: "Provvedimenti P.I. eseguiti", type: :multi, options: PI }]
      { id: "s4", title: "Sezione 4 – Danni ai componenti strutturali e provvedimenti di pronto intervento",
        blocks: [table("s4", rows, cols)] }
    end

    def s5
      rows = [["1", "Pannelli di facciata"], ["2", "Pannelli divisori interni"],
              ["3", "Distacco intonaci, rivestimenti, controsoffitti"], ["4", "Caduta tegole, comignoli, canne fumarie"],
              ["5", "Caduta parapetti, cornicioni"], ["6", "Danno a passerelle di collegamento"],
              ["7", "Danno a carroponti"], ["8", "Danno a gru a sbalzo"], ["9", "Danni a serbatoi, silos, tubazioni"],
              ["10", "Danni a scaffalature"], ["11", "Danneggiamento ai serramenti"],
              ["12", "Danno alla rete idrica, fognaria o termoidraulica"], ["13", "Danno alla rete elettrica o del gas"],
              ["14", "Danno a impianti di condizionamento, riscaldamento, ventilazione"],
              ["15", "Caduta oggetti interni o esterni non in elenco"]]
      cols = [{ key: "danno", label: "Presenza danno", type: :check },
              { key: "pi", label: "Provvedimenti P.I. eseguiti", type: :multi,
                options: [["nessuno", "Nessuno"], ["divieto", "Divieto di accesso"], ["demolizioni", "Demolizioni"],
                          ["puntelli", "Puntelli"], ["riparazioni", "Riparazioni"], ["barriere", "Barriere protettive"]] }]
      { id: "s5", title: "Sezione 5 – Danni a elementi non strutturali", blocks: [table("s5", rows, cols)] }
    end

    def s6
      rows = [["1", "Crolli o caduta oggetti da edifici adiacenti"], ["2", "Collasso di reti di distribuzione"],
              ["3", "Crolli da versanti incombenti"]]
      cols = [{ key: "assente", label: "Pericolo assente", type: :check },
              { key: "pericolo", label: "Pericolo su", type: :multi,
                options: [["edificio", "Edificio"], ["vie_interne", "Vie interne"], ["vie_accesso", "Vie d'accesso o di fuga"]] },
              { key: "pi", label: "P.I. eseguiti", type: :multi,
                options: [["nessuno", "Nessuno"], ["divieto", "Divieto di accesso"], ["barriere", "Barriere protettive"]] }]
      { id: "s6", title: "Sezione 6 – Pericolo esterno indotto da altre costruzioni, reti, versanti",
        blocks: [table("s6", rows, cols)] }
    end

    def s7
      { id: "s7", title: "Sezione 7 – Terreno e fondazioni", blocks: [
        { type: :fields, fields: [
          f("s7_morfologia", "Morfologia del sito", :select,
            options: [["", "—"], ["1", "Cresta"], ["2", "Pendio forte"], ["3", "Pendio leggero"], ["4", "Pianura"]]),
          f("s7_danni", "Danni alle fondazioni", :select,
            options: [["", "—"], ["A", "Assenti"], ["B", "Generati dal sisma"], ["C", "Acuiti dal sisma"],
                      ["D", "Preesistenti"]])
        ] }
      ] }
    end

    def s8
      risk = [["", "—"], ["basso", "Basso"], ["basso_pi", "Basso con provvedimenti"], ["alto", "Alto"]]
      { id: "s8", title: "Sezione 8 – Giudizio di agibilità", blocks: [
        { type: :fields, fields: [
          f("s8_r_strutturale", "8-A Rischio strutturale (Sez. 3 e 4)", :select, options: risk),
          f("s8_r_nonstrutt", "8-A Rischio non strutturale (Sez. 5)", :select, options: risk),
          f("s8_r_esterno", "8-A Rischio esterno (Sez. 6)", :select, options: risk),
          f("s8_r_geotecnico", "8-A Rischio geotecnico (Sez. 7)", :select, options: risk),
          f("s8_esito", "8-B Esito", :select,
            options: [["", "—"], ["A", "A – Edificio ispezionato (agibile)"],
                      ["B", "B – Temporaneamente inagibile ma agibile con provvedimenti di P.I."],
                      ["C", "C – Parzialmente inagibile"],
                      ["D", "D – Temporaneamente inagibile, da rivedere con approfondimento"],
                      ["E", "E – Inagibile"], ["F", "F – Inagibile per rischio esterno"]]),
          f("s8_accuratezza", "8-C Accuratezza della visita", :select,
            options: [["", "—"], ["1", "Solo dall'esterno"], ["2", "Parziale"], ["3", "Completa (> 2/3)"],
                      ["4", "Rilievo non effettuato"]]),
          f("s8_non_effettuato", "Rilievo non effettuato per", :select,
            options: [["", "—"], ["SR", "Sopralluogo rifiutato"], ["RU", "Rudere"], ["DM", "Demolito"],
                      ["NT", "Assenza proprietario"], ["ALTRO", "Altro"]]),
          f("s8_pi", "8-D Provvedimenti suggeriti di pronto intervento di rapida realizzazione", :textarea, wide: true),
          f("s8_unita_inagibili", "8-E Unità inagibili", :number),
          f("s8_occupanti_evacuare", "8-E Occupanti ordinari da evacuare", :number)
        ] }
      ] }
    end

    def s9
      { id: "s9", title: "Sezione 9 – Note", blocks: [
        { type: :fields, fields: [
          f("s9_danni", "Danni, provvedimenti di pronto intervento, agibilità e altro", :textarea, wide: true),
          f("s9_analisi", "Evidenze dall'analisi automatica delle immagini", :textarea, wide: true,
            hint: "Compilato dal pulsante «Importa riepilogo analisi immagini»"),
          f("s9_foto", "Foto dell'edificio (riferimenti)", :textarea, wide: true),
          f("s9_squadra", "Componenti della squadra di ispezione (uno per riga)", :textarea, wide: true)
        ] }
      ] }
    end
  end
end
