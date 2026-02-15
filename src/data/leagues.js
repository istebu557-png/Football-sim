export const LEAGUES = [
  {
    id: 'pl',
    name: 'Premier League',
    logo: 'https://media.api-sports.io/football/leagues/39.png',
    teams: [
      {
        id: 'mci',
        name: 'Manchester City',
        logo: 'https://media.api-sports.io/football/teams/50.png',
        overall: 88,
        players: [
          { id: 'mci1', name: 'Ederson', position: 'GK', rating: 89, pace: 60, shooting: 20, passing: 85, dribbling: 60, defending: 15, physical: 75 },
          { id: 'mci2', name: 'Kyle Walker', position: 'DEF', rating: 84, pace: 90, shooting: 63, passing: 76, dribbling: 77, defending: 80, physical: 82 },
          { id: 'mci3', name: 'Ruben Dias', position: 'DEF', rating: 89, pace: 62, shooting: 30, passing: 66, dribbling: 60, defending: 89, physical: 87 },
          { id: 'mci4', name: 'John Stones', position: 'DEF', rating: 85, pace: 70, shooting: 50, passing: 80, dribbling: 75, defending: 85, physical: 78 },
          { id: 'mci5', name: 'Gvardiol', position: 'DEF', rating: 83, pace: 78, shooting: 60, passing: 75, dribbling: 73, defending: 82, physical: 84 },
          { id: 'mci6', name: 'Rodri', position: 'MID', rating: 91, pace: 60, shooting: 75, passing: 88, dribbling: 80, defending: 85, physical: 84 },
          { id: 'mci7', name: 'Kevin De Bruyne', position: 'MID', rating: 91, pace: 72, shooting: 85, passing: 94, dribbling: 86, defending: 65, physical: 72 },
          { id: 'mci8', name: 'Bernardo Silva', position: 'MID', rating: 88, pace: 75, shooting: 76, passing: 86, dribbling: 92, defending: 60, physical: 65 },
          { id: 'mci9', name: 'Phil Foden', position: 'FWD', rating: 87, pace: 84, shooting: 82, passing: 85, dribbling: 89, defending: 55, physical: 60 },
          { id: 'mci10', name: 'Erling Haaland', position: 'FWD', rating: 91, pace: 89, shooting: 93, passing: 66, dribbling: 80, defending: 45, physical: 88 },
          { id: 'mci11', name: 'Jeremy Doku', position: 'FWD', rating: 80, pace: 93, shooting: 70, passing: 72, dribbling: 88, defending: 30, physical: 65 },
           // Subs
          { id: 'mci12', name: 'Ortega', position: 'GK', rating: 78, pace: 40, shooting: 15, passing: 70, dribbling: 45, defending: 12, physical: 68 },
          { id: 'mci13', name: 'Ake', position: 'DEF', rating: 82, pace: 74, shooting: 50, passing: 72, dribbling: 70, defending: 84, physical: 78 },
          { id: 'mci14', name: 'Kovacic', position: 'MID', rating: 82, pace: 68, shooting: 65, passing: 84, dribbling: 85, defending: 70, physical: 70 },
          { id: 'mci15', name: 'Grealish', position: 'FWD', rating: 83, pace: 76, shooting: 72, passing: 83, dribbling: 87, defending: 45, physical: 70 },
          { id: 'mci16', name: 'Alvarez', position: 'FWD', rating: 84, pace: 82, shooting: 80, passing: 78, dribbling: 82, defending: 50, physical: 74 }
        ]
      },
      {
        id: 'liv',
        name: 'Liverpool',
        logo: 'https://media.api-sports.io/football/teams/40.png',
        overall: 85,
        players: [
          { id: 'liv1', name: 'Alisson', position: 'GK', rating: 89, pace: 55, shooting: 20, passing: 85, dribbling: 50, defending: 15, physical: 78 },
          { id: 'liv2', name: 'Trent Alexander-Arnold', position: 'DEF', rating: 86, pace: 76, shooting: 70, passing: 91, dribbling: 78, defending: 75, physical: 70 },
          { id: 'liv3', name: 'Van Dijk', position: 'DEF', rating: 89, pace: 78, shooting: 60, passing: 72, dribbling: 70, defending: 90, physical: 86 },
          { id: 'liv4', name: 'Konate', position: 'DEF', rating: 82, pace: 75, shooting: 40, passing: 60, dribbling: 65, defending: 83, physical: 85 },
          { id: 'liv5', name: 'Robertson', position: 'DEF', rating: 85, pace: 80, shooting: 62, passing: 81, dribbling: 78, defending: 81, physical: 76 },
          { id: 'liv6', name: 'Szoboszlai', position: 'MID', rating: 84, pace: 83, shooting: 78, passing: 84, dribbling: 82, defending: 65, physical: 76 },
          { id: 'liv7', name: 'Mac Allister', position: 'MID', rating: 84, pace: 72, shooting: 78, passing: 85, dribbling: 84, defending: 72, physical: 70 },
          { id: 'liv8', name: 'Endo', position: 'MID', rating: 80, pace: 65, shooting: 60, passing: 78, dribbling: 75, defending: 82, physical: 78 },
          { id: 'liv9', name: 'Salah', position: 'FWD', rating: 89, pace: 88, shooting: 87, passing: 81, dribbling: 88, defending: 45, physical: 76 },
          { id: 'liv10', name: 'Nunez', position: 'FWD', rating: 82, pace: 90, shooting: 80, passing: 70, dribbling: 76, defending: 45, physical: 85 },
          { id: 'liv11', name: 'Diaz', position: 'FWD', rating: 84, pace: 91, shooting: 76, passing: 75, dribbling: 87, defending: 40, physical: 72 },
          // Subs
          { id: 'liv12', name: 'Kelleher', position: 'GK', rating: 76, pace: 45, shooting: 15, passing: 72, dribbling: 45, defending: 12, physical: 65 },
          { id: 'liv13', name: 'Gomez', position: 'DEF', rating: 79, pace: 80, shooting: 45, passing: 70, dribbling: 70, defending: 78, physical: 76 },
          { id: 'liv14', name: 'Jones', position: 'MID', rating: 78, pace: 75, shooting: 70, passing: 78, dribbling: 80, defending: 65, physical: 70 },
          { id: 'liv15', name: 'Jota', position: 'FWD', rating: 84, pace: 82, shooting: 84, passing: 75, dribbling: 83, defending: 50, physical: 74 },
          { id: 'liv16', name: 'Gakpo', position: 'FWD', rating: 82, pace: 83, shooting: 78, passing: 76, dribbling: 82, defending: 50, physical: 78 }
        ]
      },
       {
        id: 'ars',
        name: 'Arsenal',
        logo: 'https://media.api-sports.io/football/teams/42.png',
        overall: 86,
        players: [
          { id: 'ars1', name: 'Raya', position: 'GK', rating: 83, pace: 50, shooting: 20, passing: 82, dribbling: 50, defending: 15, physical: 70 },
          { id: 'ars2', name: 'White', position: 'DEF', rating: 83, pace: 75, shooting: 55, passing: 78, dribbling: 75, defending: 82, physical: 78 },
          { id: 'ars3', name: 'Saliba', position: 'DEF', rating: 86, pace: 80, shooting: 40, passing: 75, dribbling: 72, defending: 87, physical: 84 },
          { id: 'ars4', name: 'Gabriel', position: 'DEF', rating: 85, pace: 72, shooting: 45, passing: 70, dribbling: 65, defending: 86, physical: 85 },
          { id: 'ars5', name: 'Zinchenko', position: 'DEF', rating: 82, pace: 70, shooting: 65, passing: 84, dribbling: 82, defending: 75, physical: 70 },
          { id: 'ars6', name: 'Rice', position: 'MID', rating: 87, pace: 75, shooting: 70, passing: 84, dribbling: 80, defending: 86, physical: 85 },
          { id: 'ars7', name: 'Odegaard', position: 'MID', rating: 88, pace: 78, shooting: 80, passing: 90, dribbling: 88, defending: 60, physical: 70 },
          { id: 'ars8', name: 'Havertz', position: 'MID', rating: 82, pace: 76, shooting: 78, passing: 78, dribbling: 80, defending: 55, physical: 75 },
          { id: 'ars9', name: 'Saka', position: 'FWD', rating: 87, pace: 86, shooting: 83, passing: 82, dribbling: 88, defending: 60, physical: 74 },
          { id: 'ars10', name: 'Jesus', position: 'FWD', rating: 83, pace: 84, shooting: 80, passing: 78, dribbling: 87, defending: 50, physical: 76 },
          { id: 'ars11', name: 'Martinelli', position: 'FWD', rating: 84, pace: 89, shooting: 78, passing: 76, dribbling: 86, defending: 55, physical: 72 },
          // Subs
          { id: 'ars12', name: 'Ramsdale', position: 'GK', rating: 80, pace: 50, shooting: 15, passing: 75, dribbling: 45, defending: 12, physical: 70 },
          { id: 'ars13', name: 'Tomiyasu', position: 'DEF', rating: 80, pace: 74, shooting: 50, passing: 72, dribbling: 70, defending: 82, physical: 80 },
          { id: 'ars14', name: 'Jorginho', position: 'MID', rating: 81, pace: 50, shooting: 65, passing: 85, dribbling: 75, defending: 70, physical: 65 },
          { id: 'ars15', name: 'Trossard', position: 'FWD', rating: 81, pace: 80, shooting: 80, passing: 78, dribbling: 84, defending: 45, physical: 70 },
          { id: 'ars16', name: 'Nketiah', position: 'FWD', rating: 76, pace: 82, shooting: 75, passing: 65, dribbling: 76, defending: 35, physical: 70 }
        ]
      }
    ]
  },
  {
    id: 'll',
    name: 'La Liga',
    logo: 'https://media.api-sports.io/football/leagues/140.png',
    teams: [
      {
        id: 'rma',
        name: 'Real Madrid',
        logo: 'https://media.api-sports.io/football/teams/541.png',
        overall: 88,
        players: [
          { id: 'rma1', name: 'Courtois', position: 'GK', rating: 90, pace: 50, shooting: 20, passing: 75, dribbling: 50, defending: 15, physical: 78 },
          { id: 'rma2', name: 'Carvajal', position: 'DEF', rating: 84, pace: 78, shooting: 60, passing: 78, dribbling: 78, defending: 80, physical: 78 },
          { id: 'rma3', name: 'Militao', position: 'DEF', rating: 86, pace: 84, shooting: 50, passing: 72, dribbling: 70, defending: 86, physical: 84 },
          { id: 'rma4', name: 'Rudiger', position: 'DEF', rating: 86, pace: 82, shooting: 50, passing: 70, dribbling: 68, defending: 87, physical: 88 },
          { id: 'rma5', name: 'Mendy', position: 'DEF', rating: 82, pace: 90, shooting: 60, passing: 74, dribbling: 76, defending: 79, physical: 84 },
          { id: 'rma6', name: 'Tchouameni', position: 'MID', rating: 85, pace: 75, shooting: 70, passing: 80, dribbling: 78, defending: 84, physical: 85 },
          { id: 'rma7', name: 'Valverde', position: 'MID', rating: 88, pace: 88, shooting: 80, passing: 84, dribbling: 82, defending: 78, physical: 84 },
          { id: 'rma8', name: 'Bellingham', position: 'MID', rating: 90, pace: 82, shooting: 85, passing: 88, dribbling: 88, defending: 78, physical: 84 },
          { id: 'rma9', name: 'Vinicius Jr', position: 'FWD', rating: 90, pace: 95, shooting: 84, passing: 82, dribbling: 92, defending: 40, physical: 76 },
          { id: 'rma10', name: 'Rodrygo', position: 'FWD', rating: 86, pace: 89, shooting: 82, passing: 80, dribbling: 87, defending: 45, physical: 70 },
          { id: 'rma11', name: 'Mbappe', position: 'FWD', rating: 92, pace: 97, shooting: 90, passing: 82, dribbling: 93, defending: 40, physical: 78 }, // Assuming he's there
          // Subs
          { id: 'rma12', name: 'Lunin', position: 'GK', rating: 81, pace: 50, shooting: 15, passing: 70, dribbling: 45, defending: 12, physical: 70 },
          { id: 'rma13', name: 'Alaba', position: 'DEF', rating: 85, pace: 76, shooting: 70, passing: 83, dribbling: 78, defending: 84, physical: 76 },
          { id: 'rma14', name: 'Camavinga', position: 'MID', rating: 83, pace: 80, shooting: 70, passing: 82, dribbling: 84, defending: 80, physical: 78 },
          { id: 'rma15', name: 'Modric', position: 'MID', rating: 86, pace: 70, shooting: 75, passing: 90, dribbling: 88, defending: 65, physical: 60 },
          { id: 'rma16', name: 'Joselu', position: 'FWD', rating: 80, pace: 65, shooting: 82, passing: 68, dribbling: 72, defending: 40, physical: 82 }
        ]
      },
      {
        id: 'bar',
        name: 'Barcelona',
        logo: 'https://media.api-sports.io/football/teams/529.png',
        overall: 86,
        players: [
          { id: 'bar1', name: 'Ter Stegen', position: 'GK', rating: 89, pace: 50, shooting: 20, passing: 85, dribbling: 50, defending: 15, physical: 75 },
          { id: 'bar2', name: 'Kounde', position: 'DEF', rating: 84, pace: 80, shooting: 50, passing: 75, dribbling: 72, defending: 85, physical: 80 },
          { id: 'bar3', name: 'Araujo', position: 'DEF', rating: 86, pace: 84, shooting: 45, passing: 65, dribbling: 68, defending: 87, physical: 86 },
          { id: 'bar4', name: 'Christensen', position: 'DEF', rating: 83, pace: 70, shooting: 40, passing: 75, dribbling: 70, defending: 84, physical: 78 },
          { id: 'bar5', name: 'Cancelo', position: 'DEF', rating: 85, pace: 82, shooting: 70, passing: 84, dribbling: 86, defending: 78, physical: 72 },
          { id: 'bar6', name: 'De Jong', position: 'MID', rating: 87, pace: 80, shooting: 70, passing: 88, dribbling: 89, defending: 76, physical: 78 },
          { id: 'bar7', name: 'Gundogan', position: 'MID', rating: 86, pace: 70, shooting: 80, passing: 87, dribbling: 84, defending: 70, physical: 72 },
          { id: 'bar8', name: 'Pedri', position: 'MID', rating: 86, pace: 78, shooting: 72, passing: 87, dribbling: 89, defending: 68, physical: 65 },
          { id: 'bar9', name: 'Raphinha', position: 'FWD', rating: 83, pace: 88, shooting: 78, passing: 78, dribbling: 85, defending: 50, physical: 72 },
          { id: 'bar10', name: 'Lewandowski', position: 'FWD', rating: 88, pace: 74, shooting: 90, passing: 78, dribbling: 84, defending: 45, physical: 80 },
          { id: 'bar11', name: 'Felix', position: 'FWD', rating: 82, pace: 84, shooting: 78, passing: 80, dribbling: 86, defending: 40, physical: 68 },
          // Subs
          { id: 'bar12', name: 'Pena', position: 'GK', rating: 75, pace: 45, shooting: 15, passing: 70, dribbling: 45, defending: 12, physical: 65 },
          { id: 'bar13', name: 'Balde', position: 'DEF', rating: 81, pace: 90, shooting: 60, passing: 75, dribbling: 80, defending: 76, physical: 70 },
          { id: 'bar14', name: 'Gavi', position: 'MID', rating: 83, pace: 76, shooting: 70, passing: 80, dribbling: 84, defending: 75, physical: 75 },
          { id: 'bar15', name: 'Torres', position: 'FWD', rating: 81, pace: 82, shooting: 78, passing: 76, dribbling: 82, defending: 45, physical: 72 },
          { id: 'bar16', name: 'Yamal', position: 'FWD', rating: 78, pace: 84, shooting: 72, passing: 74, dribbling: 85, defending: 35, physical: 60 }
        ]
      }
    ]
  },
   {
    id: 'bl',
    name: 'Bundesliga',
    logo: 'https://media.api-sports.io/football/leagues/78.png',
    teams: [
      {
        id: 'bay',
        name: 'Bayern Munich',
        logo: 'https://media.api-sports.io/football/teams/157.png',
        overall: 87,
        players: [
          { id: 'bay1', name: 'Neuer', position: 'GK', rating: 87, pace: 60, shooting: 25, passing: 85, dribbling: 60, defending: 15, physical: 75 },
          { id: 'bay2', name: 'Kimmich', position: 'MID', rating: 88, pace: 70, shooting: 75, passing: 88, dribbling: 82, defending: 80, physical: 75 },
          { id: 'bay3', name: 'De Ligt', position: 'DEF', rating: 86, pace: 72, shooting: 50, passing: 70, dribbling: 68, defending: 86, physical: 85 },
          { id: 'bay4', name: 'Upamecano', position: 'DEF', rating: 83, pace: 84, shooting: 40, passing: 70, dribbling: 72, defending: 82, physical: 86 },
          { id: 'bay5', name: 'Davies', position: 'DEF', rating: 84, pace: 95, shooting: 65, passing: 76, dribbling: 84, defending: 76, physical: 78 },
          { id: 'bay6', name: 'Goretzka', position: 'MID', rating: 85, pace: 78, shooting: 80, passing: 82, dribbling: 80, defending: 80, physical: 84 },
          { id: 'bay7', name: 'Musiala', position: 'MID', rating: 87, pace: 86, shooting: 80, passing: 84, dribbling: 92, defending: 60, physical: 68 },
          { id: 'bay8', name: 'Muller', position: 'MID', rating: 82, pace: 68, shooting: 78, passing: 82, dribbling: 76, defending: 60, physical: 70 },
          { id: 'bay9', name: 'Sane', position: 'FWD', rating: 84, pace: 92, shooting: 80, passing: 78, dribbling: 86, defending: 45, physical: 74 },
          { id: 'bay10', name: 'Kane', position: 'FWD', rating: 90, pace: 74, shooting: 93, passing: 85, dribbling: 82, defending: 50, physical: 83 },
          { id: 'bay11', name: 'Coman', position: 'FWD', rating: 85, pace: 90, shooting: 78, passing: 78, dribbling: 87, defending: 40, physical: 70 },
           // Subs
          { id: 'bay12', name: 'Ulreich', position: 'GK', rating: 76, pace: 40, shooting: 15, passing: 65, dribbling: 45, defending: 12, physical: 68 },
          { id: 'bay13', name: 'Min Jae', position: 'DEF', rating: 84, pace: 78, shooting: 40, passing: 70, dribbling: 68, defending: 85, physical: 84 },
          { id: 'bay14', name: 'Laimer', position: 'MID', rating: 82, pace: 80, shooting: 70, passing: 78, dribbling: 78, defending: 80, physical: 80 },
          { id: 'bay15', name: 'Gnabry', position: 'FWD', rating: 83, pace: 84, shooting: 82, passing: 78, dribbling: 84, defending: 45, physical: 75 },
          { id: 'bay16', name: 'Tel', position: 'FWD', rating: 78, pace: 86, shooting: 76, passing: 68, dribbling: 80, defending: 35, physical: 70 }
        ]
      },
      {
        id: 'bvb',
        name: 'Dortmund',
        logo: 'https://media.api-sports.io/football/teams/165.png',
        overall: 82,
        players: [
          { id: 'bvb1', name: 'Kobel', position: 'GK', rating: 87, pace: 50, shooting: 20, passing: 75, dribbling: 50, defending: 15, physical: 78 },
          { id: 'bvb2', name: 'Ryerson', position: 'DEF', rating: 78, pace: 76, shooting: 60, passing: 72, dribbling: 74, defending: 76, physical: 80 },
          { id: 'bvb3', name: 'Hummels', position: 'DEF', rating: 83, pace: 55, shooting: 55, passing: 78, dribbling: 70, defending: 86, physical: 78 },
          { id: 'bvb4', name: 'Schlotterbeck', position: 'DEF', rating: 82, pace: 76, shooting: 45, passing: 72, dribbling: 70, defending: 83, physical: 82 },
          { id: 'bvb5', name: 'Maatsen', position: 'DEF', rating: 78, pace: 84, shooting: 60, passing: 74, dribbling: 76, defending: 74, physical: 70 },
          { id: 'bvb6', name: 'Can', position: 'MID', rating: 81, pace: 68, shooting: 65, passing: 75, dribbling: 74, defending: 80, physical: 84 },
          { id: 'bvb7', name: 'Sabitzer', position: 'MID', rating: 81, pace: 74, shooting: 76, passing: 80, dribbling: 78, defending: 72, physical: 76 },
          { id: 'bvb8', name: 'Brandt', position: 'MID', rating: 84, pace: 76, shooting: 78, passing: 84, dribbling: 85, defending: 55, physical: 70 },
          { id: 'bvb9', name: 'Malen', position: 'FWD', rating: 81, pace: 90, shooting: 78, passing: 74, dribbling: 82, defending: 45, physical: 74 },
          { id: 'bvb10', name: 'Fullkrug', position: 'FWD', rating: 81, pace: 70, shooting: 82, passing: 70, dribbling: 74, defending: 45, physical: 84 },
          { id: 'bvb11', name: 'Sancho', position: 'FWD', rating: 81, pace: 80, shooting: 74, passing: 80, dribbling: 86, defending: 40, physical: 65 },
          // Subs
          { id: 'bvb12', name: 'Meyer', position: 'GK', rating: 72, pace: 45, shooting: 15, passing: 65, dribbling: 45, defending: 12, physical: 65 },
          { id: 'bvb13', name: 'Sule', position: 'DEF', rating: 82, pace: 75, shooting: 45, passing: 70, dribbling: 68, defending: 83, physical: 86 },
          { id: 'bvb14', name: 'Ozcan', position: 'MID', rating: 78, pace: 70, shooting: 60, passing: 75, dribbling: 74, defending: 78, physical: 80 },
          { id: 'bvb15', name: 'Reus', position: 'MID', rating: 82, pace: 70, shooting: 80, passing: 82, dribbling: 82, defending: 50, physical: 65 },
          { id: 'bvb16', name: 'Adeyemi', position: 'FWD', rating: 79, pace: 94, shooting: 72, passing: 70, dribbling: 80, defending: 35, physical: 70 }
        ]
      }
    ]
  },
  {
    id: 'sa',
    name: 'Serie A',
    logo: 'https://media.api-sports.io/football/leagues/135.png',
    teams: [
      {
        id: 'int',
        name: 'Inter Milan',
        logo: 'https://media.api-sports.io/football/teams/505.png',
        overall: 85,
        players: [
          { id: 'int1', name: 'Sommer', position: 'GK', rating: 84, pace: 50, shooting: 20, passing: 78, dribbling: 50, defending: 15, physical: 72 },
          { id: 'int2', name: 'Pavard', position: 'DEF', rating: 83, pace: 74, shooting: 60, passing: 76, dribbling: 74, defending: 83, physical: 78 },
          { id: 'int3', name: 'Acerbi', position: 'DEF', rating: 82, pace: 55, shooting: 40, passing: 70, dribbling: 65, defending: 84, physical: 80 },
          { id: 'int4', name: 'Bastoni', position: 'DEF', rating: 85, pace: 76, shooting: 50, passing: 78, dribbling: 75, defending: 84, physical: 82 },
          { id: 'int5', name: 'Dumfries', position: 'DEF', rating: 81, pace: 84, shooting: 65, passing: 72, dribbling: 76, defending: 76, physical: 86 },
          { id: 'int6', name: 'Barella', position: 'MID', rating: 86, pace: 80, shooting: 74, passing: 84, dribbling: 84, defending: 76, physical: 78 },
          { id: 'int7', name: 'Calhanoglu', position: 'MID', rating: 85, pace: 72, shooting: 80, passing: 88, dribbling: 84, defending: 74, physical: 70 },
          { id: 'int8', name: 'Mkhitaryan', position: 'MID', rating: 83, pace: 76, shooting: 78, passing: 82, dribbling: 83, defending: 65, physical: 70 },
          { id: 'int9', name: 'Dimarco', position: 'DEF', rating: 83, pace: 84, shooting: 72, passing: 83, dribbling: 80, defending: 76, physical: 72 },
          { id: 'int10', name: 'Lautaro', position: 'FWD', rating: 88, pace: 82, shooting: 87, passing: 76, dribbling: 86, defending: 50, physical: 82 },
          { id: 'int11', name: 'Thuram', position: 'FWD', rating: 82, pace: 86, shooting: 78, passing: 74, dribbling: 80, defending: 45, physical: 84 },
           // Subs
          { id: 'int12', name: 'Audero', position: 'GK', rating: 76, pace: 45, shooting: 15, passing: 65, dribbling: 45, defending: 12, physical: 68 },
          { id: 'int13', name: 'De Vrij', position: 'DEF', rating: 81, pace: 60, shooting: 40, passing: 70, dribbling: 65, defending: 83, physical: 78 },
          { id: 'int14', name: 'Frattesi', position: 'MID', rating: 80, pace: 78, shooting: 74, passing: 78, dribbling: 80, defending: 72, physical: 75 },
          { id: 'int15', name: 'Carlos Augusto', position: 'DEF', rating: 79, pace: 82, shooting: 65, passing: 74, dribbling: 76, defending: 74, physical: 78 },
          { id: 'int16', name: 'Arnautovic', position: 'FWD', rating: 78, pace: 70, shooting: 78, passing: 74, dribbling: 76, defending: 40, physical: 84 }
        ]
      },
      {
        id: 'juv',
        name: 'Juventus',
        logo: 'https://media.api-sports.io/football/teams/496.png',
        overall: 82,
        players: [
          { id: 'juv1', name: 'Szczesny', position: 'GK', rating: 86, pace: 50, shooting: 20, passing: 75, dribbling: 50, defending: 15, physical: 74 },
          { id: 'juv2', name: 'Gatti', position: 'DEF', rating: 78, pace: 70, shooting: 45, passing: 65, dribbling: 65, defending: 78, physical: 84 },
          { id: 'juv3', name: 'Bremer', position: 'DEF', rating: 84, pace: 78, shooting: 40, passing: 68, dribbling: 66, defending: 85, physical: 86 },
          { id: 'juv4', name: 'Danilo', position: 'DEF', rating: 81, pace: 72, shooting: 60, passing: 76, dribbling: 72, defending: 82, physical: 78 },
          { id: 'juv5', name: 'Cambiaso', position: 'DEF', rating: 78, pace: 80, shooting: 60, passing: 74, dribbling: 78, defending: 72, physical: 70 },
          { id: 'juv6', name: 'Rabiot', position: 'MID', rating: 84, pace: 78, shooting: 74, passing: 78, dribbling: 80, defending: 78, physical: 84 },
          { id: 'juv7', name: 'Locatelli', position: 'MID', rating: 82, pace: 65, shooting: 68, passing: 82, dribbling: 78, defending: 78, physical: 76 },
          { id: 'juv8', name: 'McKennie', position: 'MID', rating: 79, pace: 76, shooting: 70, passing: 76, dribbling: 78, defending: 74, physical: 80 },
          { id: 'juv9', name: 'Kostic', position: 'MID', rating: 81, pace: 82, shooting: 75, passing: 83, dribbling: 80, defending: 65, physical: 78 },
          { id: 'juv10', name: 'Chiesa', position: 'FWD', rating: 83, pace: 88, shooting: 78, passing: 76, dribbling: 85, defending: 50, physical: 72 },
          { id: 'juv11', name: 'Vlahovic', position: 'FWD', rating: 83, pace: 80, shooting: 84, passing: 68, dribbling: 76, defending: 35, physical: 82 },
          // Subs
          { id: 'juv12', name: 'Perin', position: 'GK', rating: 79, pace: 45, shooting: 15, passing: 70, dribbling: 45, defending: 12, physical: 68 },
          { id: 'juv13', name: 'Rugani', position: 'DEF', rating: 76, pace: 60, shooting: 40, passing: 65, dribbling: 60, defending: 78, physical: 76 },
          { id: 'juv14', name: 'Miretti', position: 'MID', rating: 75, pace: 74, shooting: 68, passing: 74, dribbling: 76, defending: 60, physical: 65 },
          { id: 'juv15', name: 'Yildiz', position: 'FWD', rating: 74, pace: 82, shooting: 72, passing: 70, dribbling: 80, defending: 35, physical: 60 },
          { id: 'juv16', name: 'Milik', position: 'FWD', rating: 79, pace: 68, shooting: 80, passing: 72, dribbling: 75, defending: 40, physical: 78 }
        ]
      }
    ]
  },
   {
    id: 'l1',
    name: 'Ligue 1',
    logo: 'https://media.api-sports.io/football/leagues/61.png',
    teams: [
      {
        id: 'psg',
        name: 'PSG',
        logo: 'https://media.api-sports.io/football/teams/85.png',
        overall: 86,
        players: [
          { id: 'psg1', name: 'Donnarumma', position: 'GK', rating: 87, pace: 50, shooting: 20, passing: 74, dribbling: 50, defending: 15, physical: 78 },
          { id: 'psg2', name: 'Hakimi', position: 'DEF', rating: 84, pace: 92, shooting: 72, passing: 78, dribbling: 82, defending: 76, physical: 78 },
          { id: 'psg3', name: 'Marquinhos', position: 'DEF', rating: 87, pace: 78, shooting: 50, passing: 75, dribbling: 72, defending: 88, physical: 80 },
          { id: 'psg4', name: 'Skriniar', position: 'DEF', rating: 84, pace: 70, shooting: 45, passing: 70, dribbling: 68, defending: 86, physical: 84 },
          { id: 'psg5', name: 'Hernandez', position: 'DEF', rating: 83, pace: 80, shooting: 60, passing: 74, dribbling: 74, defending: 82, physical: 80 },
          { id: 'psg6', name: 'Ugarte', position: 'MID', rating: 81, pace: 72, shooting: 60, passing: 76, dribbling: 74, defending: 82, physical: 84 },
          { id: 'psg7', name: 'Zaire-Emery', position: 'MID', rating: 80, pace: 78, shooting: 70, passing: 78, dribbling: 80, defending: 72, physical: 74 },
          { id: 'psg8', name: 'Vitinha', position: 'MID', rating: 82, pace: 76, shooting: 72, passing: 83, dribbling: 84, defending: 70, physical: 70 },
          { id: 'psg9', name: 'Dembele', position: 'FWD', rating: 85, pace: 93, shooting: 76, passing: 80, dribbling: 89, defending: 40, physical: 65 },
          { id: 'psg10', name: 'Ramos', position: 'FWD', rating: 81, pace: 75, shooting: 80, passing: 72, dribbling: 76, defending: 45, physical: 80 },
          { id: 'psg11', name: 'Barcola', position: 'FWD', rating: 78, pace: 88, shooting: 72, passing: 72, dribbling: 82, defending: 40, physical: 65 },
          // Subs
          { id: 'psg12', name: 'Navas', position: 'GK', rating: 81, pace: 50, shooting: 15, passing: 72, dribbling: 50, defending: 12, physical: 65 },
          { id: 'psg13', name: 'Kimpembe', position: 'DEF', rating: 82, pace: 76, shooting: 45, passing: 72, dribbling: 70, defending: 83, physical: 84 },
          { id: 'psg14', name: 'Fabian', position: 'MID', rating: 80, pace: 68, shooting: 74, passing: 80, dribbling: 80, defending: 70, physical: 70 },
          { id: 'psg15', name: 'Asensio', position: 'FWD', rating: 82, pace: 78, shooting: 82, passing: 80, dribbling: 82, defending: 45, physical: 70 },
          { id: 'psg16', name: 'Kolo Muani', position: 'FWD', rating: 83, pace: 90, shooting: 78, passing: 72, dribbling: 82, defending: 45, physical: 76 }
        ]
      }
    ]
  },
  {
    id: 'tr',
    name: 'Süper Lig',
    logo: 'https://media.api-sports.io/football/leagues/203.png',
    teams: [
      {
        id: 'gal',
        name: 'Galatasaray',
        logo: 'https://media.api-sports.io/football/teams/597.png',
        overall: 78,
        players: [
          { id: 'gal1', name: 'Muslera', position: 'GK', rating: 80, pace: 45, shooting: 15, passing: 70, dribbling: 45, defending: 15, physical: 70 },
          { id: 'gal2', name: 'Boey', position: 'DEF', rating: 78, pace: 86, shooting: 60, passing: 70, dribbling: 74, defending: 75, physical: 78 },
          { id: 'gal3', name: 'Nelsson', position: 'DEF', rating: 77, pace: 65, shooting: 40, passing: 65, dribbling: 60, defending: 79, physical: 80 },
          { id: 'gal4', name: 'Sanchez', position: 'DEF', rating: 78, pace: 74, shooting: 45, passing: 68, dribbling: 68, defending: 79, physical: 82 },
          { id: 'gal5', name: 'Kohn', position: 'DEF', rating: 74, pace: 82, shooting: 60, passing: 70, dribbling: 74, defending: 68, physical: 70 },
          { id: 'gal6', name: 'Torreira', position: 'MID', rating: 80, pace: 76, shooting: 65, passing: 78, dribbling: 78, defending: 80, physical: 82 },
          { id: 'gal7', name: 'Demirbay', position: 'MID', rating: 77, pace: 65, shooting: 74, passing: 78, dribbling: 76, defending: 65, physical: 72 },
          { id: 'gal8', name: 'Mertens', position: 'MID', rating: 78, pace: 70, shooting: 78, passing: 80, dribbling: 80, defending: 45, physical: 60 },
          { id: 'gal9', name: 'Ziyech', position: 'FWD', rating: 79, pace: 74, shooting: 78, passing: 82, dribbling: 82, defending: 50, physical: 65 },
          { id: 'gal10', name: 'Icardi', position: 'FWD', rating: 80, pace: 72, shooting: 82, passing: 70, dribbling: 76, defending: 40, physical: 78 },
          { id: 'gal11', name: 'Zaha', position: 'FWD', rating: 79, pace: 86, shooting: 76, passing: 74, dribbling: 84, defending: 45, physical: 74 },
          // Subs
          { id: 'gal12', name: 'Gunay', position: 'GK', rating: 70, pace: 40, shooting: 15, passing: 60, dribbling: 45, defending: 12, physical: 65 },
          { id: 'gal13', name: 'Bardakci', position: 'DEF', rating: 76, pace: 70, shooting: 50, passing: 72, dribbling: 68, defending: 78, physical: 80 },
          { id: 'gal14', name: 'Kutlu', position: 'MID', rating: 74, pace: 70, shooting: 60, passing: 72, dribbling: 70, defending: 70, physical: 75 },
          { id: 'gal15', name: 'Akturkoglu', position: 'FWD', rating: 77, pace: 84, shooting: 74, passing: 74, dribbling: 78, defending: 45, physical: 65 },
          { id: 'gal16', name: 'Baris Alper', position: 'FWD', rating: 76, pace: 88, shooting: 70, passing: 68, dribbling: 76, defending: 60, physical: 82 }
        ]
      },
      {
        id: 'fb',
        name: 'Fenerbahçe',
        logo: 'https://media.api-sports.io/football/teams/600.png',
        overall: 78,
        players: [
          { id: 'fb1', name: 'Livakovic', position: 'GK', rating: 80, pace: 50, shooting: 20, passing: 72, dribbling: 50, defending: 15, physical: 74 },
          { id: 'fb2', name: 'Osayi-Samuel', position: 'DEF', rating: 76, pace: 90, shooting: 55, passing: 68, dribbling: 76, defending: 72, physical: 80 },
          { id: 'fb3', name: 'Becao', position: 'DEF', rating: 77, pace: 68, shooting: 40, passing: 60, dribbling: 62, defending: 79, physical: 85 },
          { id: 'fb4', name: 'Djiku', position: 'DEF', rating: 77, pace: 72, shooting: 45, passing: 70, dribbling: 68, defending: 79, physical: 78 },
          { id: 'fb5', name: 'Kadioglu', position: 'DEF', rating: 79, pace: 84, shooting: 68, passing: 78, dribbling: 82, defending: 74, physical: 76 },
          { id: 'fb6', name: 'Fred', position: 'MID', rating: 79, pace: 78, shooting: 70, passing: 78, dribbling: 80, defending: 76, physical: 76 },
          { id: 'fb7', name: 'Yuksek', position: 'MID', rating: 75, pace: 74, shooting: 60, passing: 72, dribbling: 72, defending: 76, physical: 78 },
          { id: 'fb8', name: 'Szymanski', position: 'MID', rating: 79, pace: 80, shooting: 78, passing: 78, dribbling: 80, defending: 60, physical: 72 },
          { id: 'fb9', name: 'Kahveci', position: 'FWD', rating: 78, pace: 72, shooting: 78, passing: 80, dribbling: 82, defending: 55, physical: 70 },
          { id: 'fb10', name: 'Dzeko', position: 'FWD', rating: 81, pace: 60, shooting: 84, passing: 75, dribbling: 76, defending: 45, physical: 80 },
          { id: 'fb11', name: 'Tadic', position: 'FWD', rating: 80, pace: 65, shooting: 78, passing: 84, dribbling: 82, defending: 50, physical: 75 },
          // Subs
          { id: 'fb12', name: 'Egri Bayindir', position: 'GK', rating: 70, pace: 40, shooting: 15, passing: 60, dribbling: 45, defending: 12, physical: 65 },
          { id: 'fb13', name: 'Soyuncu', position: 'DEF', rating: 77, pace: 70, shooting: 45, passing: 65, dribbling: 65, defending: 79, physical: 80 },
          { id: 'fb14', name: 'Krunic', position: 'MID', rating: 76, pace: 65, shooting: 65, passing: 76, dribbling: 74, defending: 75, physical: 75 },
          { id: 'fb15', name: 'Under', position: 'FWD', rating: 77, pace: 82, shooting: 78, passing: 75, dribbling: 80, defending: 40, physical: 68 },
          { id: 'fb16', name: 'Batshuayi', position: 'FWD', rating: 77, pace: 80, shooting: 78, passing: 68, dribbling: 76, defending: 40, physical: 78 }
        ]
      },
      {
        id: 'bjk',
        name: 'Beşiktaş',
        logo: 'https://media.api-sports.io/football/teams/603.png',
        overall: 76,
        players: [
          { id: 'bjk1', name: 'Gunok', position: 'GK', rating: 77, pace: 45, shooting: 15, passing: 70, dribbling: 45, defending: 12, physical: 70 },
          { id: 'bjk2', name: 'Svensson', position: 'DEF', rating: 74, pace: 78, shooting: 55, passing: 68, dribbling: 70, defending: 72, physical: 74 },
          { id: 'bjk3', name: 'Colley', position: 'DEF', rating: 76, pace: 68, shooting: 45, passing: 60, dribbling: 62, defending: 78, physical: 82 },
          { id: 'bjk4', name: 'Worral', position: 'DEF', rating: 74, pace: 60, shooting: 40, passing: 60, dribbling: 58, defending: 76, physical: 80 },
          { id: 'bjk5', name: 'Masuaku', position: 'DEF', rating: 76, pace: 82, shooting: 65, passing: 72, dribbling: 78, defending: 70, physical: 74 },
          { id: 'bjk6', name: 'Al-Musrati', position: 'MID', rating: 78, pace: 60, shooting: 65, passing: 78, dribbling: 72, defending: 78, physical: 82 },
          { id: 'bjk7', name: 'Gedson', position: 'MID', rating: 78, pace: 84, shooting: 70, passing: 76, dribbling: 82, defending: 74, physical: 76 },
          { id: 'bjk8', name: 'Muci', position: 'MID', rating: 76, pace: 78, shooting: 74, passing: 76, dribbling: 80, defending: 55, physical: 72 },
          { id: 'bjk9', name: 'Rashica', position: 'FWD', rating: 77, pace: 82, shooting: 74, passing: 74, dribbling: 78, defending: 55, physical: 72 },
          { id: 'bjk10', name: 'Semih', position: 'FWD', rating: 75, pace: 80, shooting: 76, passing: 68, dribbling: 78, defending: 45, physical: 78 },
          { id: 'bjk11', name: 'Muleka', position: 'FWD', rating: 74, pace: 82, shooting: 72, passing: 68, dribbling: 74, defending: 40, physical: 76 },
           // Subs
          { id: 'bjk12', name: 'Destanoglu', position: 'GK', rating: 72, pace: 45, shooting: 15, passing: 65, dribbling: 45, defending: 12, physical: 65 },
          { id: 'bjk13', name: 'Amarte', position: 'DEF', rating: 74, pace: 65, shooting: 50, passing: 65, dribbling: 65, defending: 75, physical: 78 },
          { id: 'bjk14', name: 'Ucan', position: 'MID', rating: 75, pace: 68, shooting: 70, passing: 78, dribbling: 76, defending: 65, physical: 70 },
          { id: 'bjk15', name: 'Ghezzal', position: 'FWD', rating: 76, pace: 70, shooting: 75, passing: 80, dribbling: 80, defending: 45, physical: 60 },
          { id: 'bjk16', name: 'Tosun', position: 'FWD', rating: 75, pace: 65, shooting: 78, passing: 70, dribbling: 72, defending: 40, physical: 75 }
        ]
      }
    ]
  }
];
