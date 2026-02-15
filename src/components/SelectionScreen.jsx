
import React, { useState } from 'react';
import { LEAGUES } from '../data/leagues';
import TeamCard from './TeamCard';

const SelectionScreen = ({ onStart }) => {
  const [homeLeague, setHomeLeague] = useState(LEAGUES[0]);
  const [homeTeam, setHomeTeam] = useState(LEAGUES[0].teams[0]);

  const [awayLeague, setAwayLeague] = useState(LEAGUES[1]);
  const [awayTeam, setAwayTeam] = useState(LEAGUES[1].teams[0]);

  // Handler for league change
  const handleHomeLeagueChange = (e) => {
    const league = LEAGUES.find(l => l.id === e.target.value);
    setHomeLeague(league);
    setHomeTeam(league.teams[0]); // Reset team to first in league
  };

  const handleHomeTeamChange = (e) => {
    const team = homeLeague.teams.find(t => t.id === e.target.value);
    setHomeTeam(team);
  };

  const handleAwayLeagueChange = (e) => {
    const league = LEAGUES.find(l => l.id === e.target.value);
    setAwayLeague(league);
    setAwayTeam(league.teams[0]);
  };

  const handleAwayTeamChange = (e) => {
    const team = awayLeague.teams.find(t => t.id === e.target.value);
    setAwayTeam(team);
  };

  const handleStartMatch = () => {
    if (homeTeam && awayTeam && homeTeam.id !== awayTeam.id) {
      onStart(homeTeam, awayTeam);
    } else {
        alert("Please select different teams.");
    }
  };

  return (
    <div className="selection-screen">
      <h1>Match Setup</h1>

      <div className="selection-container">
        {/* Home Selection */}
        <div className="side-selector home">
          <h2>Home Team</h2>
          <div className="selector-controls">
            <select value={homeLeague.id} onChange={handleHomeLeagueChange}>
              {LEAGUES.map(league => (
                <option key={league.id} value={league.id}>{league.name}</option>
              ))}
            </select>

            <select value={homeTeam.id} onChange={handleHomeTeamChange}>
              {homeLeague.teams.map(team => (
                <option key={team.id} value={team.id}>{team.name}</option>
              ))}
            </select>
          </div>
          <TeamCard team={homeTeam} side="home" />
        </div>

        <div className="vs-badge">VS</div>

        {/* Away Selection */}
        <div className="side-selector away">
          <h2>Away Team</h2>
          <div className="selector-controls">
            <select value={awayLeague.id} onChange={handleAwayLeagueChange}>
              {LEAGUES.map(league => (
                <option key={league.id} value={league.id}>{league.name}</option>
              ))}
            </select>

            <select value={awayTeam.id} onChange={handleAwayTeamChange}>
              {awayLeague.teams.map(team => (
                <option key={team.id} value={team.id}>{team.name}</option>
              ))}
            </select>
          </div>
          <TeamCard team={awayTeam} side="away" />
        </div>
      </div>

      <button className="start-btn" onClick={handleStartMatch} disabled={!homeTeam || !awayTeam}>
        KICK OFF
      </button>
    </div>
  );
};

export default SelectionScreen;
