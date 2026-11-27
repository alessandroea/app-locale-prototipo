-- App Locale – V04 – membri e dati di esempio (da V03)

insert into public.members (email,name,color) values
  ('alessandro@ecclesieagazzi.com','Alessandro','#1677ff'),
  ('giovanni.assolari95@gmail.com','Giovanni','#30a46c'),
  ('assolarigiovanni@icloud.com','Giovanni','#30a46c')
on conflict (email) do update set name=excluded.name, color=excluded.color;

insert into public.places (id,name,category,lat,lng,info) values
  ('kew','Kew Gardens – Victoria Gate','Giardino botanico',51.4786,-0.293,'[["Tipo", "Giardini botanici (UNESCO)"], ["Inverno", "Evento serale di Natale con biglietti a fascia oraria"], ["Consiglio", "Entrata a orario: inutile arrivare molto prima"]]'::jsonb),
  ('sheen','Passaggio a livello Sheen Lane','Incrocio',51.4677,-0.2668,'[["Tipo", "Passaggio a livello vicino a Mortlake"], ["Nota", "Nelle ore di punta le barriere restano giù a lungo"], ["Alternativa", "Clifford Avenue / Chalker''s Corner"]]'::jsonb),
  ('green','Richmond Green','Parco',51.4613,-0.3063,'[["Tipo", "Prato pubblico, cricket d''estate"], ["Intorno", "Pub, caffè e teatro"], ["Consiglio", "Nei weekend di sole si riempie dopo pranzo"]]'::jsonb),
  ('station','Stazione di Richmond','Trasporti',51.4631,-0.3017,'[["Linee", "District, Overground, South Western Railway"], ["Bus", "Fermate davanti alla stazione"], ["Consiglio", "Nei giorni di partita a Twickenham è molto affollata"]]'::jsonb),
  ('bridge','Richmond Bridge e Riverside','Fiume',51.4572,-0.3071,'[["Tipo", "Ponte storico sul Tamigi"], ["Attenzione", "Con l''alta marea il lungofiume si allaga"], ["Consiglio", "Prendete la strada sopra quando è allagato"]]'::jsonb),
  ('terrace','Richmond Hill – The Terrace','Panorama',51.4545,-0.302,'[["Tipo", "Belvedere sul Tamigi"], ["Curiosità", "Vista protetta da una legge del 1902"], ["Consiglio", "Bellissima al tramonto"]]'::jsonb),
  ('park','Richmond Park – Pembroke Lodge','Parco',51.4446,-0.2925,'[["Tipo", "Parco reale con cervi"], ["Attenzione", "Tenersi a distanza dai cervi, soprattutto in autunno"], ["Vista", "Da King Henry''s Mound si vede St Paul''s"]]'::jsonb),
  ('twick','Twickenham Stadium','Sport',51.456,-0.3415,'[["Tipo", "Stadio del rugby"], ["Giorni di partita", "Treni e strade pieni da ore prima"], ["Consiglio", "Meglio arrivare a piedi da Twickenham"]]'::jsonb),
  ('putney','Putney High Street','Strada',51.461,-0.2165,'[["Tipo", "Via dei negozi vicino al ponte di Putney"], ["Bus", "Molte linee verso il centro"], ["Consiglio", "Ore di punta lente verso il ponte"]]'::jsonb);

insert into public.place_reports (place_id,status,is_demo,demo_offset_min,author_id) values
  ('kew','affollato',true,8,null),
  ('kew','coda',true,14,null),
  ('kew','affollato',true,22,null),
  ('sheen','coda',true,5,null),
  ('sheen','coda',true,11,null),
  ('green','tranquillo',true,18,null),
  ('station','ritardi',true,9,null),
  ('station','affollato',true,16,null),
  ('bridge','chiuso',true,28,null),
  ('park','tranquillo',true,35,null),
  ('putney','affollato',true,12,null);

insert into public.posts (id,kind,category,place_id,place_label,lat,lng,radius_m,body,author_id,demo_author,is_demo,demo_offset_min,base_votes,created_at,expires_at) values
  ('9a9976ae-afa5-4d1f-a53b-f01d51c371ad','q','eventi','kew','Kew Gardens – Victoria Gate',51.4786,-0.293,1000,'Perché c''è così tanta coda alla Victoria Gate?',null,'priya',true,25,9,now(),now()+interval '3 hours'),
  ('419f340c-39f6-4804-8cff-61d7f1d0e77f','n','traffico','sheen','Passaggio a livello Sheen Lane',51.4677,-0.2668,1000,'Barriere giù da 12 minuti, coda fino a Upper Richmond Road',null,'ben',true,8,6,now(),now()+interval '1 hours'),
  ('a3c23e81-2005-4ffe-af7e-d7ac5869b76d','q','eventi','green','Richmond Green',51.4613,-0.3063,1000,'Cosa succede sul Green stasera? Si sente musica',null,'fede',true,40,3,now(),now()+interval '3 hours'),
  ('fd7ef139-0be4-4d1e-82d4-799267b79a3e','n','trasporti','station','Stazione di Richmond',51.4631,-0.3017,1000,'District line sospesa verso Turnham Green: bus sostitutivi davanti alla stazione',null,'mark',true,15,11,now(),now()+interval '2 hours'),
  ('dd5d5e12-08de-47c8-aa36-1b8302b447be','q','natura','park','Richmond Park – Pembroke Lodge',51.4446,-0.2925,1000,'Cervi vicino al sentiero di Pembroke Lodge: si passa tranquilli?',null,'sara',true,62,5,now(),now()+interval '3 hours'),
  ('e6a4eae6-1764-45fb-8766-27b5b5425ad8','q','sport','twick','Twickenham Stadium',51.456,-0.3415,1000,'Sabato c''è partita? Vorrei evitare il treno',null,'priya',true,170,4,now(),now()+interval '24 hours'),
  ('051bf9df-1f80-43cc-93fd-655a9afd60fa','n','info','bridge','Richmond Bridge e Riverside',51.4572,-0.3071,1000,'Riverside allagato con l''alta marea, passate dalla strada sopra',null,'giulia',true,30,8,now(),now()+interval '3 hours'),
  ('688e94d6-4f2a-41de-8349-88bb82c8c15c','q','cibo','putney','Putney High Street',51.461,-0.2165,1000,'Qualche posto aperto per un caffè dopo le 18 qui vicino?',null,'hannah',true,20,2,now(),now()+interval '3 hours'),
  ('d7f7c95d-6a81-4593-8fb7-066f4f83d053','q','info','terrace','Richmond Hill – The Terrace',51.4545,-0.302,1000,'Com''è la visibilità dalla terrazza adesso?',null,'tom',true,48,3,now(),now()+interval '3 hours'),
  ('aa723612-9feb-43ed-af9e-087134f1f163','n','eventi','putney','Putney High Street',51.461,-0.2165,1000,'Mercatino di Natale davanti alla chiesa fino alle 20',null,'ben',true,55,5,now(),now()+interval '5 hours');

insert into public.answers (id,post_id,body,distance_m,author_id,demo_author,is_demo,demo_offset_min,base_votes) values
  ('ccf21566-f394-41b1-9e88-ef60a557d57c','9a9976ae-afa5-4d1f-a53b-f01d51c371ad','È l''evento di Natale: si entra per fascia oraria, la coda scorre in una decina di minuti.',60,null,'tom',true,19,12),
  ('f61b120a-475a-4918-bd1f-b24bc880c375','9a9976ae-afa5-4d1f-a53b-f01d51c371ad','Se avete il biglietto per un orario più tardi non serve arrivare adesso.',140,null,'giulia',true,12,5),
  ('69519bc7-c38c-4c3f-94df-ac970ae25886','419f340c-39f6-4804-8cff-61d7f1d0e77f','Confermo, meglio girare da Clifford Avenue.',220,null,'hannah',true,4,3),
  ('888bd6eb-8fb2-4073-b439-2cdc4a9bb008','a3c23e81-2005-4ffe-af7e-d7ac5869b76d','Prove del concerto di Natale della scuola, finiscono verso le 19.',90,null,'mark',true,31,4),
  ('32d07e35-8c62-4ae8-90a2-c8b6ad807613','fd7ef139-0be4-4d1e-82d4-799267b79a3e','I bus sostitutivi passano circa ogni 10 minuti.',40,null,'priya',true,9,2),
  ('8ed659d3-55d3-4049-80d5-adbe8644394f','dd5d5e12-08de-47c8-aa36-1b8302b447be','Sì, ma restate a 50 m: in questo periodo i maschi sono nervosi.',300,null,'priya',true,50,7),
  ('fc9e2eb6-7f20-4c9a-ae0f-ade76a429d9a','dd5d5e12-08de-47c8-aa36-1b8302b447be','Cani al guinzaglio, mi raccomando.',500,null,'ben',true,41,2),
  ('a66d9d18-9793-438b-8176-bea2d6d63812','e6a4eae6-1764-45fb-8766-27b5b5425ad8','Sì, nel pomeriggio: treni pieni da mezzogiorno, meglio la mattina.',700,null,'mark',true,150,6),
  ('458144e8-129b-4cc0-8ee3-f1878a068e48','051bf9df-1f80-43cc-93fd-655a9afd60fa','Grazie, salvato le scarpe!',80,null,'tom',true,22,1),
  ('1ce10a30-bd44-4899-bcdd-6555b68a848e','688e94d6-4f2a-41de-8349-88bb82c8c15c','Un paio di caffè sulla High Street chiudono alle 19, i pub servono caffè anche più tardi.',120,null,'fede',true,14,3),
  ('001eb8fa-3bff-4017-97f8-f20d03bce4cb','d7f7c95d-6a81-4593-8fb7-066f4f83d053','Un po'' di foschia sul fiume, ma il tramonto si vede bene.',30,null,'giulia',true,35,4);

update public.posts set best_answer_id='ccf21566-f394-41b1-9e88-ef60a557d57c' where id='9a9976ae-afa5-4d1f-a53b-f01d51c371ad';

update public.posts set best_answer_id='888bd6eb-8fb2-4073-b439-2cdc4a9bb008' where id='a3c23e81-2005-4ffe-af7e-d7ac5869b76d';

update public.posts set best_answer_id='8ed659d3-55d3-4049-80d5-adbe8644394f' where id='dd5d5e12-08de-47c8-aa36-1b8302b447be';

update public.posts set best_answer_id='001eb8fa-3bff-4017-97f8-f20d03bce4cb' where id='d7f7c95d-6a81-4593-8fb7-066f4f83d053';
