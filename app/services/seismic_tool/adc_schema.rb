# frozen_string_literal: true

module SeismicTool
  # "Modello A-DC" – Scheda per il rilievo del danno ai beni culturali – CHIESE
  # (PCM-DPC / MiBAC 2006, Gruppo di lavoro per la salvaguardia e la prevenzione
  # dei beni culturali dai rischi naturali). Sections A1–A27 plus the abacus of
  # the 28 collapse mechanisms (A16), which drives the damage index of A17.
  module AdcSchema
    module_function

    S = AedesSchema

    def f(*args, **kw) = S.f(*args, **kw)
    def table(*args, **kw) = S.table(*args, **kw)
    def display(spec, value) = S.display(spec, value)

    def label = "Modello A-DC – Chiese (MiBAC 2006)"

    def description
      "Scheda per il rilievo del danno ai beni culturali – Chiese (Modello A-DC, PCM-DPC / MiBAC 2006). " \
        "Il danno sismico si registra per ciascuno dei 28 meccanismi di collasso (A16); l'indice di danno (A17) è calcolato."
    end

    def summary_key = "a23_note"

    def sections
      @sections ||= [a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20,
                     a21, a22, a23, a24, a25, a26, a27].freeze
    end

    def section(id) = sections.find { |s| s[:id] == id }

    def keys
      @keys ||= sections.flat_map do |s|
        s[:blocks].flat_map do |b|
          if b[:type] == :fields
            b[:fields].map { |x| x[:key] }
          else
            b[:rows].flat_map { |r| b[:columns].map { |c| "#{b[:key]}_#{r[0]}_#{c[:key]}" } }
          end
        end
      end.freeze
    end

    def field(key)
      sections.each { |s| s[:blocks].each { |b| (b[:fields] || []).each { |x| return x if x[:key] == key } } }
      nil
    end

    # ---- derived values (A17) -----------------------------------------------
    MECHANISMS = [
      "Ribaltamento della facciata", "Meccanismi nella sommità della facciata", "Meccanismi nel piano della facciata",
      "Protiro – nartece", "Risposta trasversale dell'aula", "Meccanismi di taglio nelle pareti laterali (risposta longitudinale)",
      "Risposta longitudinale del colonnato nelle chiese a più navate", "Volte della navata centrale",
      "Volte delle navate laterali", "Ribaltamento delle pareti di estremità del transetto",
      "Meccanismi di taglio nelle pareti laterali del transetto", "Volte del transetto", "Archi trionfali",
      "Cupola – tamburo/tiburio", "Lanterna", "Ribaltamento dell'abside",
      "Meccanismi di taglio nel presbiterio o nell'abside", "Volte del presbiterio o dell'abside",
      "Elementi di copertura – pareti laterali dell'aula", "Elementi di copertura – transetto",
      "Elementi di copertura – abside e presbiterio", "Ribaltamento delle cappelle",
      "Meccanismi di taglio nelle pareti delle cappelle", "Volte delle cappelle",
      "Interazioni in prossimità di irregolarità plano-altimetriche (corpi adiacenti, archi rampanti)",
      "Aggetti (vele, guglie, pinnacoli, statue)", "Torre campanaria", "Cella campanaria"
    ].freeze

    # n = mechanisms assessed (level 0..5 given), d = sum of the levels, id = d / 5n.
    def computed(data)
      levels = (1..MECHANISMS.size).filter_map do |i|
        v = data["a16_#{i}_livello"]
        v.to_s.match?(/\A[0-5]\z/) ? v.to_i : nil
      end
      return { "a17_n" => nil, "a17_d" => nil, "a17_id" => nil } if levels.empty?

      n = levels.size
      d = levels.sum
      { "a17_n" => n.to_s, "a17_d" => d.to_s, "a17_id" => format("%.3f", d.to_f / (5 * n)) }
    end

    # ---- sections ------------------------------------------------------------
    LEVEL = [["", "—"], ["0", "0 – assenza di danno"], ["1", "1 – lieve"], ["2", "2 – moderato"], ["3", "3 – grave"],
             ["4", "4 – molto grave"], ["5", "5 – crollo"]].freeze
    DAMAGE_KIND = [["", "—"], ["sismico", "Danno sismico"], ["pregresso", "Danno pregresso"],
                   ["aggravamento", "Aggravamento"]].freeze

    def a1
      { id: "a1", title: "A1 – Dati della scheda", blocks: [{ type: :fields, fields: [
        f("a1_data", "Data", :date), f("a1_progressivo", "N° progressivo (a cura dell'ufficio)"),
        f("a1_scheda", "N° scheda")
      ] }] }
    end

    def a2
      { id: "a2", title: "A2 – Riferimento verticale", blocks: [{ type: :fields, fields: [
        f("a2_tipo", "Tipo di bene", :select, options: [["", "—"], ["complesso", "Bene complesso"], ["individuo", "Bene individuo"]]),
        f("a2_complesso", "Denominazione bene complesso"), f("a2_n_schede", "Numero schede beni componenti", :number),
        f("a2_livello_sup", "Codice livello superiore"),
        f("a2_tipologia", "Tipologia", :multi,
          options: [%w[chiesa Chiesa], %w[canonica Canonica], %w[palazzo Palazzo], %w[castello Castello],
                    %w[torre Torre], ["archeologico", "Bene archeologico"], %w[altro Altro]]),
        f("a2_tipologia_altro", "Tipologia – altro"),
        f("a2_pianta", "Pianta", :multi,
          options: [%w[regolare Regolare], ["cortili", "Con cortili"], ["ali_aperte", "Ad ali aperte"],
                    %w[lineare Lineare], %w[altro Altro]]),
        f("a2_pianta_altro", "Pianta – altro")
      ] }] }
    end

    def a3
      { id: "a3", title: "A3 – Localizzazione geografico-amministrativa", blocks: [{ type: :fields, fields: [
        f("a3_regione", "Regione"), f("a3_provincia", "Provincia"), f("a3_istat", "Codice ISTAT comune"),
        f("a3_comune", "Comune"), f("a3_localita", "Località"),
        f("a3_via_tipo", "Indirizzo – tipo", :select,
          options: [["", "—"], ["1", "Via"], ["2", "Corso"], ["3", "Vicolo"], ["4", "Piazza"], ["5", "Località"]]),
        f("a3_indirizzo", "Indirizzo"), f("a3_civico", "N° civico"),
        f("a3_sezione", "Sezione censuaria"), f("a3_aggregato", "N° complesso o aggregato"),
        f("a3_edificio", "N° edificio"), f("a3_foglio", "Foglio"), f("a3_data_cat", "Data (catasto)", :date),
        f("a3_particelle", "Particelle"), f("a3_sub", "Sub.")
      ] }] }
    end

    def a4
      { id: "a4", title: "A4 – Coordinate UTM", blocks: [{ type: :fields, fields: [
        f("a4_quadrante", "Quadrante"), f("a4_est", "Longitudine Est (x)"), f("a4_nord", "Latitudine Nord (y)"),
        f("a4_gps", "Lettura GPS", :bool)
      ] }] }
    end

    def a5
      { id: "a5", title: "A5 – Oggetto", blocks: [{ type: :fields, fields: [
        f("a5_denominazione", "Denominazione bene", :text, wide: true),
        f("a5_storica", "Denominazione storica", :text, wide: true),
        f("a5_anno", "Datazione – anno"), f("a5_secolo", "Datazione – secolo"), f("a5_epoca", "Datazione – epoca"),
        f("a5_trasformazione", "Ultima trasformazione"),
        f("a5_proprieta", "Proprietà"), f("a5_proprieta_tipo", "Proprietà – tipo"),
        f("a5_utilizzatore", "Utilizzatore"), f("a5_utilizzatore_tipo", "Utilizzatore – tipo")
      ] }] }
    end

    def a6
      uses = [["cattedrale", "Cattedrale / Duomo"], ["parrocchiale", "Chiesa parrocchiale"], ["oratorio", "Oratorio"],
              ["santuario", "Santuario"], ["museo", "Museo"], ["auditorium", "Auditorium"], ["servizi", "Servizi"],
              ["altro", "Altro"]]
      cols = [{ key: "continuo", label: "Continuo", type: :check }, { key: "saltuario", label: "Saltuario", type: :check },
              { key: "non_utilizzato", label: "Non utilizzato", type: :check },
              { key: "affollamento", label: "Affollamento", type: :text }]
      { id: "a6", title: "A6 – Destinazione d'uso attuale", blocks: [
        table("a6", uses, cols),
        { type: :fields, fields: [f("a6_altro", "Altro uso (specificare)")] }
      ] }
    end

    def a7
      { id: "a7", title: "A7 – Caratteristiche del sito", blocks: [{ type: :fields, fields: [
        f("a7_sito", "Sito", :select,
          options: [["", "—"], ["piano", "In piano"], ["rilievo", "Su rilievo / su cresta / su vetta"],
                    ["riporto", "Su riporto"], ["pendio", "In pendio / su versante"], ["avvallamento", "Avvallamento"]])
      ] }] }
    end

    def a8
      { id: "a8", title: "A8 – Contesto urbano e posizione", blocks: [{ type: :fields, fields: [
        f("a8_contesto", "Contesto urbano", :multi,
          options: [["centro_urbano", "Centro urbano"], ["periferia", "Periferia urbana"],
                    ["industriale", "Area industriale – commerciale"], ["agricola", "Area agricola"],
                    ["storico", "Centro storico"]]),
        f("a8_posizione", "Posizione", :select,
          options: [["", "—"], ["isolata", "Isolata"], ["connessa", "Connessa con altri edifici"], ["altro", "Altro"]]),
        f("a8_lati", "Connessa su n. lati", :number), f("a8_altro", "Altro (specificare)")
      ] }] }
    end

    def a9
      { id: "a9", title: "A9 – Infrastrutture", blocks: [{ type: :fields, fields: [
        f("a9_infra", "Infrastrutture", :multi,
          options: [["pedonale", "Accesso pedonale"], ["carrabile", "Accesso carrabile"],
                    ["altezza_4m", "Accesso con altezza inferiore a 4 metri"], ["pesanti", "Accesso con mezzi pesanti"],
                    ["rete_viaria", "Rete viaria idonea in relazione al rischio"],
                    ["parcheggio", "Parcheggio nelle vicinanze"], ["spazi_aperti", "Spazi aperti a disposizione"]]),
        f("a9_altro", "Altro")
      ] }] }
    end

    def a10
      rows = [["frana", "Insediamento minacciato da frana"], ["alluvione", "Insediamento in zona alluvionabile"],
              ["industriale", "Insediamento soggetto a minacce di tipo industriale"],
              ["altre", "Insediamento soggetto ad altre minacce naturali"]]
      cols = [{ key: "diretta", label: "Rilevazione diretta", type: :check },
              { key: "acquisite", label: "Informazioni acquisite", type: :check }]
      { id: "a10", title: "A10 – Presenza di rischio", blocks: [table("a10", rows, cols)] }
    end

    def a11
      rows = [["affreschi", "Affreschi"], ["mosaici", "Mosaici"], ["stucchi", "Stucchi"], ["arazzi", "Arazzi"],
              ["altari", "Altari / statue"], ["libri", "Libri / Stampe"], ["dipinti", "Dipinti mobili su vario supporto"],
              ["arredi", "Arredi (soffitti, amboni, pulpito, stalli corali)"], ["plastiche", "Decorazioni plastiche mobili"],
              ["carta", "Manufatti in carta e pergamena"], ["reperti", "Reperti archeologici"], ["altri", "Altri"]]
      cols = [{ key: "num", label: "Num.", type: :number }, { key: "sup", label: "Superficie (m²)", type: :number }]
      { id: "a11", title: "A11 – Tipologia dei beni artistici presenti", blocks: [table("a11", rows, cols)] }
    end

    def a12
      { id: "a12", title: "A12 – Documentazione fotografica", blocks: [{ type: :fields, fields: [
        f("a12_da", "Realizzata da"), f("a12_si", "Documentazione fotografica presente", :select, options: S::YESNO)
      ] }] }
    end

    def a13
      { id: "a13", title: "A13 – Compilatore scheda", blocks: [{ type: :fields, fields: [
        f("a13_cognome", "Cognome"), f("a13_nome", "Nome"), f("a13_ente", "Ente/ufficio di appartenenza"),
        f("a13_tel", "Telefono"), f("a13_email", "E-mail")
      ] }] }
    end

    def a14
      { id: "a14", title: "A14 – Riferimento scheda della vulnerabilità delle chiese", blocks: [{ type: :fields, fields: [
        f("a14_scheda", "N° scheda"), f("a14_data", "Data", :date), f("a14_ente", "Ente")
      ] }] }
    end

    def a15
      { id: "a15", title: "A15 – Stato di manutenzione generale", blocks: [{ type: :fields, fields: [
        f("a15_stato", "Stato di manutenzione", :select,
          options: [["", "—"], ["buono", "Buono"], ["discreto", "Discreto"], ["scadente", "Scadente"],
                    ["pessimo", "Pessimo"], ["lavori", "In corso lavori"]]),
        f("a15_lesioni", "Eventuali precedenti lesioni esistenti", :select,
          options: [["", "—"], ["no", "NO"], ["limitate", "SI – limitate"], ["estese", "SI – estese"], ["gravi", "SI – gravi"]])
      ] }] }
    end

    def a16
      rows = MECHANISMS.each_with_index.map { |m, i| [(i + 1).to_s, m] }
      cols = [{ key: "livello", label: "Livello di danno (0–5)", type: :select, options: LEVEL },
              { key: "tipo", label: "Identificazione del danno", type: :select, options: DAMAGE_KIND }]
      { id: "a16", title: "A16 – Danno sismico (abaco dei meccanismi di collasso delle chiese)",
        blocks: [table("a16", rows, cols)] }
    end

    def a17
      { id: "a17", title: "A17 – Indice di danno", blocks: [{ type: :fields, fields: [
        f("a17_n", "n = numero dei meccanismi valutati", :number, hint: "Calcolato dai livelli di danno inseriti in A16"),
        f("a17_d", "d = punteggio totale di danno", :number, hint: "Somma dei livelli di danno"),
        f("a17_id", "id = d / 5n", :text, hint: "Indice di danno")
      ] }] }
    end

    def a18
      { id: "a18", title: "A18 – Agibilità", blocks: [{ type: :fields, fields: [
        f("a18_esito", "Esito", :select,
          options: [["", "—"], ["agibile", "Agibile"], ["parziale", "Parzialmente agibile"],
                    ["provvedimenti", "Agibile con provvedimenti"], ["temp_inagibile", "Temporaneamente inagibile"],
                    ["inagibile", "Inagibile"], ["esterne", "Inagibile per cause esterne"]]),
        f("a18_parti", "Parti agibili", :textarea), f("a18_provvedimenti", "Provvedimenti (anche nella tabella A20)", :textarea),
        f("a18_verifica", "Verifica più accurata", :select,
          options: [["", "—"], ["esperti", "Si consiglia visita di esperti"], ["altro", "Altro"]]),
        f("a18_esterne", "Cause esterne", :textarea)
      ] }] }
    end

    def a19
      { id: "a19", title: "A19 – Tipo di visita", blocks: [{ type: :fields, fields: [
        f("a19_tipo", "Tipo di visita", :select,
          options: [["", "—"], ["completa", "Completa"], ["parziale", "Parziale"], ["esterno", "Solo dall'esterno"]]),
        f("a19_motivi", "Motivi ostativi", :textarea)
      ] }] }
    end

    def a20
      rows = [["1", "Revisione manto di copertura"], ["2", "Copertura provvisoria"], ["3", "Puntellamenti"],
              ["4", "Rimozione delle macerie"], ["5", "Transennamenti / recinzioni / protezioni"],
              ["6", "Consolidamenti localizzati"], ["7", "Messa in opera di cerchiatura e/o tiranti"],
              ["8", "Ripristino smaltimento delle acque meteoriche"], ["9", "Monitoraggio"],
              ["10", "Protezioni o consolidamenti su opere d'arte fisse"],
              ["11", "Catalogazione e smontaggio delle parti pericolanti"], ["12", "Sgombero opere d'arte mobili"],
              ["13", "Raccolta sistematica dei frammenti"], ["14", "Ricovero e protezione dei frammenti"]]
      cols = [{ key: "lim", label: "* interventi limitati", type: :check },
              { key: "est", label: "** interventi estesi", type: :check }]
      { id: "a20", title: "A20 – Provvedimenti di pronto intervento suggeriti", blocks: [table("a20", rows, cols)] }
    end

    def a21
      { id: "a21", title: "A21 – Danni all'apparato decorativo e alle opere d'arte", blocks: [{ type: :fields, fields: [
        f("a21_desc", "A21.1 – Descrizione apparato decorativo o opera d'arte", :textarea, wide: true),
        f("a21_danno", "A21.2 – Descrizione danno", :textarea, wide: true),
        f("a21_provv", "A21.3 – Provvedimenti provvisionali sugli apparati decorativi e sgombero opere d'arte mobili",
          :textarea, wide: true),
        f("a21_storico", "Si consiglia intervento dello storico dell'arte", :bool),
        f("a21_costo", "Stima del costo per la salvaguardia delle opere d'arte (€)", :number)
      ] }] }
    end

    def a22
      { id: "a22", title: "A22 – Descrizione e stima sommaria delle opere necessarie", blocks: [{ type: :fields, fields: [
        f("a22_1", "A22.1 – Opere di ripristino strutturale (nuovi danni e danni pregressi aggravati)", :textarea, wide: true),
        f("a22_1_costo", "Stima del costo per il ripristino strutturale (€)", :number),
        f("a22_2", "A22.2 – Opere di finitura, impiantistica e miglioramento sismico collegate", :textarea, wide: true),
        f("a22_2_costo", "Stima del costo opere di finitura, impiantistica e miglioramento sismico (€)", :number),
        f("a22_3", "A22.3 – Opere di pronto intervento (anche costo del P.I. «a finire»)", :textarea, wide: true),
        f("a22_3_costo", "Stima del costo opere di pronto intervento (€)", :number)
      ] }] }
    end

    def a23
      { id: "a23", title: "A23 – Note", blocks: [{ type: :fields, fields: [
        f("a23_note", "Altri danni non rilevabili dalla scheda (es. solai di calpestio, pavimentazioni…); evidenze dall'analisi delle immagini",
          :textarea, wide: true)
      ] }] }
    end

    def a24
      rows = [["aula", "Aula (compresi navate, cappelle, transetti)"], ["abside", "Abside"],
              ["facciata", "Facciata principale"], ["campanile", "Campanile"], ["coperture", "Coperture chiesa"]]
      cols = [{ key: "larghezza", label: "Larghezza (m)", type: :number },
              { key: "lunghezza", label: "Lunghezza (m)", type: :number },
              { key: "superficie", label: "Superficie (m²)", type: :number },
              { key: "altezza", label: "Altezza (m)", type: :number }]
      { id: "a24", title: "A24 – Dati dimensionali", blocks: [
        { type: :fields, fields: [f("a24_tipo", "Dati", :select, options: [["", "—"], ["stimati", "Stimati"], ["rilevati", "Rilevati"]])] },
        table("a24", rows, cols)
      ] }
    end

    def a25
      { id: "a25", title: "A25 – Elaborati grafici", blocks: [{ type: :fields, fields: [
        f("a25_elaborati", "Piante, sezioni, prospetti, illustrazione di dissesti particolari", :textarea, wide: true)
      ] }] }
    end

    def a26
      { id: "a26", title: "A26 – Documentazione allegata", blocks: [{ type: :fields, fields: [
        f("a26_si", "Documentazione allegata", :select, options: S::YESNO),
        f("a26_elenco", "Elenco", :textarea, wide: true)
      ] }] }
    end

    def a27
      { id: "a27", title: "A27 – Squadra che ha eseguito il rilievo", blocks: [{ type: :fields, fields: [
        f("a27_sisma", "Sisma"), f("a27_com", "C.O.M."), f("a27_squadra", "Squadra n."),
        f("a27_componenti", "Componenti (cognome e nome, qualifica, ente di appartenenza – uno per riga)", :textarea, wide: true)
      ] }] }
    end
  end
end
