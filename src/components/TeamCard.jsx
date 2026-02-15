
import React from 'react';
import { calculateTeamStats, getStarRating } from '../utils/gameLogic';

const TeamCard = ({ team, side }) => {
  if (!team) return <div className="team-card empty">Select a Team</div>;

  const stats = calculateTeamStats(team.players);
  const stars = getStarRating(stats.overall);

  return (
    <div className={`team-card ${side}`}>
      <div className="team-header">
        <img src={team.logo} alt={team.name} className="team-logo" />
        <h2>{team.name}</h2>
      </div>

      <div className="star-rating">
        {[...Array(5)].map((_, i) => (
          <span key={i} className={i < stars ? "star filled" : "star"}>★</span>
        ))}
      </div>

      <div className="team-stats">
        <div className="stat-row">
          <span>OVR</span>
          <span className={`stat-value ${stats.overall > 85 ? 'high' : stats.overall > 75 ? 'mid' : 'low'}`}>
            {stats.overall}
          </span>
        </div>
        <div className="stat-details">
          <div className="stat-item">
            <small>ATT</small>
            <span>{stats.attack}</span>
          </div>
          <div className="stat-item">
            <small>MID</small>
            <span>{stats.midfield}</span>
          </div>
          <div className="stat-item">
            <small>DEF</small>
            <span>{stats.defense}</span>
          </div>
        </div>
      </div>
    </div>
  );
};

export default TeamCard;
