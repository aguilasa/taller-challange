import React from 'react';
import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/react';
import '@testing-library/jest-dom';
import { App } from './App.jsx';

describe('App', () => {
  it('renders the charge form', () => {
    render(<App />);
    expect(screen.getByText('Payments Admin')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Create charge' })).toBeInTheDocument();
  });
});
