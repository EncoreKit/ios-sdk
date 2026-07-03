//
//  SDUIFallbackConfig.swift
//  Encore
//
//  Fallback JSON configuration for server-driven UI
//  This is the source of truth for the offer sheet layout
//

import Foundation

/// Contains fallback SDUI configurations
/// In the future, these can be fetched from a server instead
enum SDUIFallbackConfig {
    
    /// Parses the presentation style from the embedded JSON config
    static var presentationStyle: SDUIPresentationStyle {
        guard let data = offerSheetJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let styleString = json["presentationStyle"] as? String,
              let style = SDUIPresentationStyle(rawValue: styleString) else {
            return .default
        }
        return style
    }
    
    // MARK: - Default Offer Sheet

    /// The offer sheet JSON configuration — production fallback, always available.
    /// Source: offer-sheet-config.json
    static let offerSheetJSON = """
{
  "version": "2.4.3",
  "presentationStyle": "fullScreenCover",
  "respectsSafeArea": true,
  "presentationDetents": [
    1.0
  ],
  "cornerRadius": 0,
  "showDragIndicator": false,
  "root": {
    "zStack": {
      "alignment": "top",
      "children": [
        {
          "gradient": {
            "direction": "topToBottom",
            "colors": [
              {
                "color": {
                  "binding": {
                    "key": "appDominantColor",
                    "fallback": {
                      "hex": "94348C"
                    }
                  },
                  "lighten": 0.73
                },
                "opacity": 1.0
              },
              {
                "color": {
                  "hex": "#FFFFFF"
                },
                "opacity": 1.0
              },
              {
                "color": {
                  "hex": "#FFFFFF"
                },
                "opacity": 1.0
              }
            ],
            "style": {
              "ignoresSafeArea": true
            }
          }
        },
        {
          "vStack": {
            "spacing": 0,
            "children": [
              {
                "conditional": {
                  "condition": {
                    "stateEquals": "claimed"
                  },
                  "ifTrue": {
                    "zStack": {
                      "alignment": "top",
                      "children": [
                        {
                          "asyncImage": {
                            "url": "https://storage.googleapis.com/encore-assets-prod/sdk-assets/confettiImage.png",
                            "contentMode": "fit",
                            "style": {
                              "frame": {
                                "maxWidth": "infinity"
                              },
                              "ignoresSafeArea": true
                            },
                            "placeholderColor": {
                              "hex": "00000000"
                            },
                            "aspectRatio": 1.4
                          }
                        },
                        {
                          "vStack": {
                            "spacing": 0,
                            "alignment": "center",
                            "children": [
                              {
                                "hStack": {
                                  "alignment": "center",
                                  "children": [
                                    {
                                      "button": {
                                        "content": {
                                          "systemImage": {
                                            "systemName": "chevron.left",
                                            "font": {
                                              "size": 18,
                                              "weight": "semibold"
                                            },
                                            "color": {
                                              "hex": "707070"
                                            }
                                          }
                                        },
                                        "action": {
                                          "type": "setState",
                                          "setState": "congrats"
                                        }
                                      }
                                    },
                                    {
                                      "spacer": {}
                                    },
                                    {
                                      "button": {
                                        "content": {
                                          "zStack": {
                                            "alignment": "center",
                                            "children": [
                                              {
                                                "shape": {
                                                  "type": "circle",
                                                  "fillColor": {
                                                    "hex": "FFFFFFFF"
                                                  },
                                                  "style": {
                                                    "frame": {
                                                      "width": 32,
                                                      "height": 32
                                                    },
                                                    "shadow": {
                                                      "color": {
                                                        "hex": "000000"
                                                      },
                                                      "radius": 6,
                                                      "x": 0,
                                                      "y": 2,
                                                      "opacity": 0.06
                                                    }
                                                  }
                                                }
                                              },
                                              {
                                                "systemImage": {
                                                  "systemName": "xmark",
                                                  "font": {
                                                    "size": 14,
                                                    "weight": "semibold"
                                                  },
                                                  "color": {
                                                    "hex": "707070"
                                                  }
                                                }
                                              }
                                            ]
                                          }
                                        },
                                        "action": "close"
                                      }
                                    }
                                  ],
                                  "style": {
                                    "padding": {
                                      "top": 64
                                    },
                                    "frame": {
                                      "maxWidth": "infinity"
                                    }
                                  }
                                }
                              },
                              {
                                "spacer": {}
                              },
                              {
                                "hStack": {
                                  "spacing": -14,
                                  "alignment": "center",
                                  "children": [
                                    {
                                      "vStack": {
                                        "spacing": 0,
                                        "alignment": "center",
                                        "children": [
                                          {
                                            "appIcon": {
                                              "style": {
                                                "frame": {
                                                  "width": 64,
                                                  "height": 64
                                                },
                                                "cornerRadius": 16
                                              }
                                            }
                                          },
                                          {
                                            "text": {
                                              "text": "${appName}",
                                              "font": {
                                                "size": 16,
                                                "weight": "semibold"
                                              },
                                              "color": {
                                                "hex": "292D32"
                                              },
                                              "lineLimit": 1,
                                              "style": {
                                                "padding": {
                                                  "top": 12
                                                }
                                              }
                                            }
                                          },
                                          {
                                            "text": {
                                              "text": "${trialValue} ${trialUnit} free",
                                              "font": {
                                                "size": 13,
                                                "weight": "regular"
                                              },
                                              "color": {
                                                "hex": "6B6B70"
                                              },
                                              "lineLimit": 1,
                                              "style": {
                                                "padding": {
                                                  "top": 2
                                                }
                                              }
                                            }
                                          }
                                        ],
                                        "style": {
                                          "padding": {
                                            "top": 18,
                                            "leading": 16,
                                            "bottom": 18,
                                            "trailing": 16
                                          },
                                          "cornerRadius": 20,
                                          "backgroundColor": {
                                            "hex": "FFFFFFFF"
                                          },
                                          "frame": {
                                            "width": 150
                                          },
                                          "rotation": -5,
                                          "shadow": {
                                            "color": {
                                              "hex": "000000"
                                            },
                                            "opacity": 0.12,
                                            "radius": 18,
                                            "x": 0,
                                            "y": 4
                                          }
                                        }
                                      }
                                    },
                                    {
                                      "vStack": {
                                        "spacing": 0,
                                        "alignment": "center",
                                        "children": [
                                          {
                                            "asyncImage": {
                                              "urlBinding": "offerLogoImage",
                                              "contentMode": "fit",
                                              "placeholderColor": {
                                                "hex": "FFE5E5EA"
                                              },
                                              "style": {
                                                "frame": {
                                                  "width": 64,
                                                  "height": 64
                                                },
                                                "cornerRadius": 16,
                                                "clipShape": {
                                                  "rectangle": {
                                                    "cornerRadius": 16
                                                  }
                                                }
                                              }
                                            }
                                          },
                                          {
                                            "text": {
                                              "text": "",
                                              "textBinding": "offerAdvertiserName",
                                              "font": {
                                                "size": 16,
                                                "weight": "semibold"
                                              },
                                              "color": {
                                                "hex": "292D32"
                                              },
                                              "lineLimit": 1,
                                              "style": {
                                                "padding": {
                                                  "top": 12
                                                }
                                              }
                                            }
                                          },
                                          {
                                            "text": {
                                              "text": "",
                                              "textBinding": "offerPerk",
                                              "font": {
                                                "size": 13,
                                                "weight": "regular"
                                              },
                                              "color": {
                                                "hex": "6B6B70"
                                              },
                                              "lineLimit": 1,
                                              "style": {
                                                "padding": {
                                                  "top": 2
                                                }
                                              }
                                            }
                                          }
                                        ],
                                        "style": {
                                          "padding": {
                                            "top": 18,
                                            "leading": 16,
                                            "bottom": 18,
                                            "trailing": 16
                                          },
                                          "cornerRadius": 20,
                                          "backgroundColor": {
                                            "hex": "FFFFFFFF"
                                          },
                                          "frame": {
                                            "width": 150
                                          },
                                          "rotation": 5,
                                          "shadow": {
                                            "color": {
                                              "hex": "000000"
                                            },
                                            "opacity": 0.12,
                                            "radius": 18,
                                            "x": 0,
                                            "y": 4
                                          }
                                        }
                                      }
                                    }
                                  ],
                                  "style": {
                                    "padding": {
                                      "top": 0
                                    }
                                  }
                                }
                              },
                              {
                                "text": {
                                  "text": "Congratulations!",
                                  "font": {
                                    "size": 36,
                                    "weight": "bold"
                                  },
                                  "color": {
                                    "hex": "000000"
                                  },
                                  "multilineAlignment": "center",
                                  "lineHeight": 1.1,
                                  "style": {
                                    "padding": {
                                      "top": 28
                                    }
                                  }
                                }
                              },
                              {
                                "text": {
                                  "text": "Your ${appName} and ${selectedAdvertiserName} offers are both active.",
                                  "font": {
                                    "size": 18,
                                    "weight": "medium"
                                  },
                                  "color": {
                                    "hex": "000000"
                                  },
                                  "multilineAlignment": "center",
                                  "lineHeight": 1.2,
                                  "style": {
                                    "padding": {
                                      "top": 12,
                                      "leading": 8,
                                      "trailing": 8
                                    }
                                  }
                                }
                              },
                              {
                                "spacer": {}
                              },
                              {
                                "button": {
                                  "content": {
                                    "text": {
                                      "text": "Explore ${appName}",
                                      "font": {
                                        "size": 16,
                                        "weight": "semibold"
                                      },
                                      "color": {
                                        "hex": "FFFFFFFF"
                                      },
                                      "multilineAlignment": "center"
                                    }
                                  },
                                  "action": "close",
                                  "style": {
                                    "frame": {
                                      "maxWidth": "infinity"
                                    },
                                    "padding": {
                                      "top": 17,
                                      "bottom": 17
                                    },
                                    "cornerRadius": 9999,
                                    "backgroundColor": {
                                      "binding": {
                                        "key": "appDominantColor",
                                        "fallback": {
                                          "hex": "94348C"
                                        }
                                      }
                                    },
                                    "shadow": {
                                      "color": {
                                        "binding": {
                                          "key": "appDominantColor",
                                          "fallback": {
                                            "hex": "94348C"
                                          }
                                        }
                                      },
                                      "radius": 14,
                                      "x": 0,
                                      "y": 6,
                                      "opacity": 0.3
                                    }
                                  }
                                }
                              }
                            ],
                            "style": {
                              "frame": {
                                "maxWidth": "infinity",
                                "maxHeight": "infinity",
                                "alignment": "top"
                              },
                              "padding": {
                                "leading": 20,
                                "trailing": 20,
                                "bottom": 35
                              }
                            }
                          }
                        }
                      ]
                    }
                  },
                  "ifFalse": {
                    "conditional": {
                      "condition": {
                        "stateEquals": "congrats"
                      },
                      "ifTrue": {
                        "vStack": {
                          "spacing": 0,
                          "alignment": "center",
                          "children": [
                            {
                              "hStack": {
                                "alignment": "center",
                                "children": [
                                  {
                                    "spacer": {}
                                  },
                                  {
                                    "button": {
                                      "content": {
                                        "zStack": {
                                          "alignment": "center",
                                          "children": [
                                            {
                                              "shape": {
                                                "type": "circle",
                                                "fillColor": {
                                                  "hex": "FFFFFFFF"
                                                },
                                                "style": {
                                                  "frame": {
                                                    "width": 32,
                                                    "height": 32
                                                  },
                                                  "shadow": {
                                                    "color": {
                                                      "hex": "000000"
                                                    },
                                                    "radius": 6,
                                                    "x": 0,
                                                    "y": 2,
                                                    "opacity": 0.06
                                                  }
                                                }
                                              }
                                            },
                                            {
                                              "systemImage": {
                                                "systemName": "xmark",
                                                "font": {
                                                  "size": 14,
                                                  "weight": "semibold"
                                                },
                                                "color": {
                                                  "hex": "292D32"
                                                }
                                              }
                                            }
                                          ]
                                        }
                                      },
                                      "action": "close"
                                    }
                                  }
                                ],
                                "style": {
                                  "padding": {
                                    "top": 64
                                  },
                                  "frame": {
                                    "maxWidth": "infinity"
                                  }
                                }
                              }
                            },
                            {
                              "text": {
                                "text": "Congratulations. Your ${appName} trial is active!",
                                "font": {
                                  "size": 32,
                                  "weight": "semibold"
                                },
                                "color": {
                                  "hex": "000000"
                                },
                                "lineHeight": 1.1,
                                "multilineAlignment": "center",
                                "style": {
                                  "padding": {
                                    "top": 95
                                  }
                                }
                              }
                            },
                            {
                              "text": {
                                "text": "Now claim your free ${selectedAdvertiserName}",
                                "font": {
                                  "size": 18,
                                  "weight": "medium"
                                },
                                "color": {
                                  "hex": "000000"
                                },
                                "multilineAlignment": "center",
                                "style": {
                                  "padding": {
                                    "top": 12,
                                    "leading": 16,
                                    "trailing": 16
                                  }
                                },
                                "lineHeight": 1.2
                              }
                            },
                            {
                              "vStack": {
                                "spacing": 12,
                                "alignment": "center",
                                "children": [
                                  {
                                    "hStack": {
                                      "spacing": 12,
                                      "alignment": "center",
                                      "children": [
                                        {
                                          "appIcon": {
                                            "style": {
                                              "frame": {
                                                "width": 44,
                                                "height": 44
                                              },
                                              "cornerRadius": 10
                                            }
                                          }
                                        },
                                        {
                                          "vStack": {
                                            "spacing": 2,
                                            "alignment": "leading",
                                            "children": [
                                              {
                                                "text": {
                                                  "text": "${appName}",
                                                  "font": {
                                                    "size": 16,
                                                    "weight": "semibold"
                                                  },
                                                  "color": {
                                                    "hex": "292D32"
                                                  },
                                                  "lineLimit": 1
                                                }
                                              },
                                              {
                                                "text": {
                                                  "text": "${trialValue} ${trialUnit} free trial",
                                                  "font": {
                                                    "size": 14,
                                                    "weight": "regular"
                                                  },
                                                  "color": {
                                                    "hex": "6B6B70"
                                                  },
                                                  "lineLimit": 1
                                                }
                                              }
                                            ]
                                          }
                                        },
                                        {
                                          "spacer": {}
                                        },
                                        {
                                          "text": {
                                            "text": "Active",
                                            "font": {
                                              "size": 15,
                                              "weight": "semibold"
                                            },
                                            "color": {
                                              "hex": "1FBD6F"
                                            }
                                          }
                                        }
                                      ],
                                      "style": {
                                        "padding": {
                                          "top": 14,
                                          "leading": 16,
                                          "bottom": 14,
                                          "trailing": 16
                                        },
                                        "cornerRadius": 18,
                                        "backgroundColor": {
                                          "hex": "FFFFFFFF"
                                        },
                                        "shadow": {
                                          "color": {
                                            "hex": "000000"
                                          },
                                          "radius": 12,
                                          "x": 0,
                                          "y": 4,
                                          "opacity": 0.05
                                        },
                                        "borderWidth": 1,
                                        "borderColor": {
                                          "hex": "D5D5D5"
                                        }
                                      }
                                    }
                                  },
                                  {
                                    "hStack": {
                                      "spacing": 12,
                                      "alignment": "center",
                                      "children": [
                                        {
                                          "asyncImage": {
                                            "urlBinding": "offerLogoImage",
                                            "contentMode": "fit",
                                            "placeholderColor": {
                                              "hex": "FFE5E5EA"
                                            },
                                            "style": {
                                              "frame": {
                                                "width": 44,
                                                "height": 44
                                              },
                                              "cornerRadius": 10,
                                              "clipShape": {
                                                "rectangle": {
                                                  "cornerRadius": 10
                                                }
                                              }
                                            }
                                          }
                                        },
                                        {
                                          "vStack": {
                                            "spacing": 2,
                                            "alignment": "leading",
                                            "children": [
                                              {
                                                "text": {
                                                  "text": "",
                                                  "textBinding": "offerAdvertiserName",
                                                  "font": {
                                                    "size": 16,
                                                    "weight": "semibold"
                                                  },
                                                  "color": {
                                                    "hex": "292D32"
                                                  },
                                                  "lineLimit": 1
                                                }
                                              },
                                              {
                                                "text": {
                                                  "text": "",
                                                  "textBinding": "offerPerk",
                                                  "font": {
                                                    "size": 14,
                                                    "weight": "regular"
                                                  },
                                                  "color": {
                                                    "hex": "6B6B70"
                                                  },
                                                  "lineLimit": 1
                                                }
                                              }
                                            ]
                                          }
                                        },
                                        {
                                          "spacer": {}
                                        },
                                        {
                                          "text": {
                                            "text": "Pending",
                                            "font": {
                                              "size": 15,
                                              "weight": "semibold"
                                            },
                                            "color": {
                                              "hex": "8E8E93"
                                            }
                                          }
                                        }
                                      ],
                                      "style": {
                                        "padding": {
                                          "top": 14,
                                          "leading": 16,
                                          "bottom": 14,
                                          "trailing": 16
                                        },
                                        "cornerRadius": 18,
                                        "backgroundColor": {
                                          "hex": "FFFFFFFF"
                                        },
                                        "shadow": {
                                          "color": {
                                            "hex": "000000"
                                          },
                                          "radius": 12,
                                          "x": 0,
                                          "y": 4,
                                          "opacity": 0.05
                                        },
                                        "borderWidth": 1,
                                        "borderColor": {
                                          "hex": "D5D5D5"
                                        }
                                      }
                                    }
                                  }
                                ],
                                "style": {
                                  "padding": {
                                    "top": 28
                                  },
                                  "frame": {
                                    "maxWidth": "infinity"
                                  }
                                }
                              }
                            },
                            {
                              "spacer": {}
                            },
                            {
                              "conditional": {
                                "condition": {
                                  "valueEquals": {
                                    "key": "selectedOfferIsFreeTrial",
                                    "value": "false"
                                  }
                                },
                                "ifTrue": {
                                  "text": {
                                    "text": "You'll be sent to ${selectedAdvertiserName}.",
                                    "font": {
                                      "size": 13,
                                      "weight": "regular"
                                    },
                                    "color": {
                                      "hex": "6B6B70"
                                    },
                                    "multilineAlignment": "center",
                                    "style": {
                                      "padding": {
                                        "bottom": 12,
                                        "leading": 10,
                                        "trailing": 10
                                      }
                                    }
                                  }
                                },
                                "ifFalse": {
                                  "vStack": {
                                    "spacing": 2,
                                    "alignment": "center",
                                    "children": [
                                      {
                                        "text": {
                                          "font": {
                                            "size": 13,
                                            "weight": "regular"
                                          },
                                          "color": {
                                            "hex": "6B6B70"
                                          },
                                          "multilineAlignment": "center",
                                          "text": "You'll be sent to ${selectedAdvertiserName}."
                                        }
                                      },
                                      {
                                        "text": {
                                          "font": {
                                            "size": 13,
                                            "weight": "regular"
                                          },
                                          "color": {
                                            "hex": "6B6B70"
                                          },
                                          "multilineAlignment": "center",
                                          "text": "No payment now, cancel anytime."
                                        }
                                      }
                                    ],
                                    "style": {
                                      "padding": {
                                        "bottom": 12,
                                        "leading": 10,
                                        "trailing": 10
                                      }
                                    }
                                  }
                                }
                              }
                            },
                            {
                              "conditional": {
                                "condition": {
                                  "valueEquals": {
                                    "key": "selectedOfferIsFreeTrial",
                                    "value": "false"
                                  }
                                },
                                "ifTrue": {
                                  "button": {
                                    "content": {
                                      "text": {
                                        "text": "Claim your ${selectedAdvertiserName} offer",
                                        "font": {
                                          "size": 16,
                                          "weight": "semibold"
                                        },
                                        "color": {
                                          "hex": "FFFFFFFF"
                                        },
                                        "multilineAlignment": "center"
                                      }
                                    },
                                    "action": {
                                      "type": "claimOffer",
                                      "onSuccessState": "claimed"
                                    },
                                    "style": {
                                      "frame": {
                                        "maxWidth": "infinity"
                                      },
                                      "padding": {
                                        "top": 17,
                                        "bottom": 17
                                      },
                                      "cornerRadius": 9999,
                                      "backgroundColor": {
                                        "binding": {
                                          "key": "appDominantColor",
                                          "fallback": {
                                            "hex": "94348C"
                                          }
                                        }
                                      },
                                      "shadow": {
                                        "color": {
                                          "binding": {
                                            "key": "appDominantColor",
                                            "fallback": {
                                              "hex": "94348C"
                                            }
                                          }
                                        },
                                        "radius": 14,
                                        "x": 0,
                                        "y": 6,
                                        "opacity": 0.3
                                      }
                                    }
                                  }
                                },
                                "ifFalse": {
                                  "button": {
                                    "content": {
                                      "text": {
                                        "text": "Claim your free ${selectedAdvertiserName}",
                                        "font": {
                                          "size": 16,
                                          "weight": "semibold"
                                        },
                                        "color": {
                                          "hex": "FFFFFFFF"
                                        },
                                        "multilineAlignment": "center"
                                      }
                                    },
                                    "action": {
                                      "type": "claimOffer",
                                      "onSuccessState": "claimed"
                                    },
                                    "style": {
                                      "frame": {
                                        "maxWidth": "infinity"
                                      },
                                      "padding": {
                                        "top": 17,
                                        "bottom": 17
                                      },
                                      "cornerRadius": 9999,
                                      "backgroundColor": {
                                        "binding": {
                                          "key": "appDominantColor",
                                          "fallback": {
                                            "hex": "94348C"
                                          }
                                        }
                                      },
                                      "shadow": {
                                        "color": {
                                          "binding": {
                                            "key": "appDominantColor",
                                            "fallback": {
                                              "hex": "94348C"
                                            }
                                          }
                                        },
                                        "radius": 14,
                                        "x": 0,
                                        "y": 6,
                                        "opacity": 0.3
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          ],
                          "style": {
                            "frame": {
                              "maxWidth": "infinity",
                              "maxHeight": "infinity",
                              "alignment": "top"
                            },
                            "padding": {
                              "leading": 20,
                              "trailing": 20,
                              "bottom": 35
                            }
                          }
                        }
                      },
                      "ifFalse": {
                        "vStack": {
                          "spacing": 0,
                          "children": [
                            {
                              "vStack": {
                                "spacing": 6,
                                "alignment": "center",
                                "children": [
                                  {
                                    "text": {
                                      "text": "",
                                      "font": {
                                        "size": 28,
                                        "weight": "semibold"
                                      },
                                      "lineHeight": 1.12,
                                      "multilineAlignment": "center",
                                      "segments": [
                                        {
                                          "text": "Get ${trialValue} ${trialUnit} of ${appName} for ",
                                          "color": {
                                            "hex": "292D32"
                                          }
                                        },
                                        {
                                          "text": "FREE",
                                          "color": {
                                            "binding": {
                                              "key": "appDominantColor",
                                              "fallback": {
                                                "hex": "94348C"
                                              }
                                            }
                                          }
                                        },
                                        {
                                          "text": " by claiming the offer below",
                                          "color": {
                                            "hex": "292D32"
                                          }
                                        }
                                      ]
                                    }
                                  }
                                ],
                                "style": {
                                  "padding": {
                                    "top": 88,
                                    "leading": 24,
                                    "trailing": 24,
                                    "bottom": 43
                                  },
                                  "frame": {
                                    "maxWidth": "infinity"
                                  }
                                }
                              }
                            },
                            {
                              "hStack": {
                                "spacing": 12,
                                "alignment": "center",
                                "children": [
                                  {
                                    "appIcon": {
                                      "style": {
                                        "frame": {
                                          "width": 52,
                                          "height": 52
                                        },
                                        "cornerRadius": 12
                                      }
                                    }
                                  },
                                  {
                                    "vStack": {
                                      "spacing": 2,
                                      "alignment": "leading",
                                      "children": [
                                        {
                                          "text": {
                                            "text": "${appName}",
                                            "font": {
                                              "size": 18,
                                              "weight": "semibold"
                                            },
                                            "color": {
                                              "hex": "222222"
                                            },
                                            "lineLimit": 1
                                          }
                                        },
                                        {
                                          "text": {
                                            "text": "${trialValue} ${trialUnit} free access",
                                            "font": {
                                              "size": 14,
                                              "weight": "regular"
                                            },
                                            "color": {
                                              "hex": "222222",
                                              "opacity": 0.6
                                            },
                                            "lineLimit": 1
                                          }
                                        }
                                      ]
                                    }
                                  },
                                  {
                                    "spacer": {}
                                  }
                                ],
                                "style": {
                                  "padding": {
                                    "top": 16,
                                    "leading": 16,
                                    "bottom": 16,
                                    "trailing": 16
                                  },
                                  "cornerRadius": 24,
                                  "backgroundColor": {
                                    "hex": "#FFFFFF"
                                  },
                                  "shadow": {
                                    "color": {
                                      "hex": "#000000"
                                    },
                                    "radius": 12,
                                    "x": 0,
                                    "y": 4,
                                    "opacity": 0.06
                                  },
                                  "relativeWidth": 0.7,
                                  "gradientBorder": {
                                    "colors": [
                                      {
                                        "binding": {
                                          "key": "appDominantColor",
                                          "fallback": {
                                            "hex": "94348C"
                                          }
                                        },
                                        "opacity": 0.1
                                      },
                                      {
                                        "binding": {
                                          "key": "appDominantColor",
                                          "fallback": {
                                            "hex": "94348C"
                                          }
                                        },
                                        "opacity": 0.1
                                      }
                                    ],
                                    "width": 1,
                                    "cornerRadius": 24
                                  }
                                }
                              }
                            },
                            {
                              "systemImage": {
                                "systemName": "plus",
                                "font": {
                                  "size": 26,
                                  "weight": "semibold"
                                },
                                "color": {
                                  "binding": {
                                    "key": "appDominantColor",
                                    "fallback": {
                                      "hex": "94348C"
                                    }
                                  }
                                },
                                "style": {
                                  "frame": {
                                    "maxWidth": "infinity"
                                  },
                                  "padding": {
                                    "top": 23,
                                    "bottom": 17
                                  }
                                }
                              }
                            },
                            {
                              "scrollView": {
                                "axis": "horizontal",
                                "showsIndicators": false,
                                "scrollTargetBehavior": "viewAligned",
                                "contentMargins": {
                                  "horizontal": 91
                                },
                                "content": {
                                  "hStack": {
                                    "spacing": -24,
                                    "children": [
                                      {
                                        "forEach": {
                                          "dataSource": "offers",
                                          "itemTemplate": {
                                            "button": {
                                              "action": {
                                                "type": "selectOffer"
                                              },
                                              "style": {
                                                "frame": {
                                                  "width": 210,
                                                  "height": 260
                                                },
                                                "scrollTransition": {
                                                  "scale": 0.8,
                                                  "opacity": 0.5,
                                                  "rotation": 5
                                                }
                                              },
                                              "content": {
                                                "zStack": {
                                                  "alignment": "top",
                                                  "children": [
                                                    {
                                                      "shape": {
                                                        "type": "roundedRectangle",
                                                        "cornerRadius": 24,
                                                        "fillColor": {
                                                          "hex": "FFFFFFFF"
                                                        },
                                                        "style": {
                                                          "frame": {
                                                            "maxWidth": "infinity",
                                                            "maxHeight": "infinity"
                                                          }
                                                        }
                                                      }
                                                    },
                                                    {
                                                      "shape": {
                                                        "type": "roundedRectangle",
                                                        "cornerRadius": 24,
                                                        "fillColor": {
                                                          "opacity": 0.15,
                                                          "binding": "offerDominantColor",
                                                          "fallback": {
                                                            "hex": "FFCCCCCC"
                                                          }
                                                        },
                                                        "style": {
                                                          "frame": {
                                                            "maxWidth": "infinity",
                                                            "maxHeight": "infinity"
                                                          },
                                                          "cornerRadius": 24,
                                                          "scrollFade": {
                                                            "centeredOpacity": 1.0,
                                                            "offCenterOpacity": 0.0
                                                          }
                                                        }
                                                      }
                                                    },
                                                    {
                                                      "shape": {
                                                        "type": "roundedRectangle",
                                                        "cornerRadius": 24,
                                                        "fillColor": {
                                                          "hex": "00000000"
                                                        },
                                                        "style": {
                                                          "frame": {
                                                            "maxWidth": "infinity",
                                                            "maxHeight": "infinity"
                                                          },
                                                          "cornerRadius": 24,
                                                          "innerShadow": {
                                                            "color": {
                                                              "darken": 0.32,
                                                              "opacity": 0.2,
                                                              "binding": "offerDominantColor",
                                                              "fallback": {
                                                                "hex": "FFCCCCCC"
                                                              }
                                                            },
                                                            "x": -13,
                                                            "y": 0,
                                                            "blur": 15
                                                          },
                                                          "scrollFade": {
                                                            "centeredOpacity": 1.0,
                                                            "offCenterOpacity": 0.0
                                                          }
                                                        }
                                                      }
                                                    },
                                                    {
                                                      "vStack": {
                                                        "spacing": 0,
                                                        "alignment": "center",
                                                        "children": [
                                                          {
                                                            "spacer": {}
                                                          },
                                                          {
                                                            "vStack": {
                                                              "spacing": 12,
                                                              "alignment": "center",
                                                              "children": [
                                                                {
                                                                  "text": {
                                                                    "text": "Free trial",
                                                                    "font": {
                                                                      "size": 12,
                                                                      "weight": "medium"
                                                                    },
                                                                    "color": {
                                                                      "hex": "292D32"
                                                                    },
                                                                    "style": {
                                                                      "padding": {
                                                                        "top": 4,
                                                                        "bottom": 4,
                                                                        "leading": 8,
                                                                        "trailing": 8
                                                                      },
                                                                      "cornerRadius": 16,
                                                                      "backgroundColor": {
                                                                        "hex": "FFFFFFFF"
                                                                      }
                                                                    }
                                                                  }
                                                                },
                                                                {
                                                                  "vStack": {
                                                                    "spacing": 11,
                                                                    "alignment": "center",
                                                                    "children": [
                                                                      {
                                                                        "asyncImage": {
                                                                          "urlBinding": "offerLogoImage",
                                                                          "contentMode": "fit",
                                                                          "placeholderColor": {
                                                                            "opacity": 0.25,
                                                                            "binding": "offerDominantColor",
                                                                            "fallback": {
                                                                              "hex": "FFCCCCCC"
                                                                            }
                                                                          },
                                                                          "style": {
                                                                            "frame": {
                                                                              "width": 52,
                                                                              "height": 52
                                                                            },
                                                                            "cornerRadius": 14,
                                                                            "clipShape": {
                                                                              "rectangle": {
                                                                                "cornerRadius": 14
                                                                              }
                                                                            },
                                                                            "shadow": {
                                                                              "color": {
                                                                                "hex": "000000"
                                                                              },
                                                                              "radius": 2,
                                                                              "x": 0,
                                                                              "y": 2,
                                                                              "opacity": 0.15
                                                                            }
                                                                          }
                                                                        }
                                                                      },
                                                                      {
                                                                        "vStack": {
                                                                          "spacing": 4,
                                                                          "alignment": "center",
                                                                          "children": [
                                                                            {
                                                                              "text": {
                                                                                "text": "",
                                                                                "textBinding": "offerAdvertiserName",
                                                                                "font": {
                                                                                  "size": 18,
                                                                                  "weight": "semibold"
                                                                                },
                                                                                "color": {
                                                                                  "hex": "292D32"
                                                                                },
                                                                                "lineLimit": 2,
                                                                                "multilineAlignment": "center"
                                                                              }
                                                                            },
                                                                            {
                                                                              "text": {
                                                                                "text": "",
                                                                                "font": {
                                                                                  "size": 14,
                                                                                  "weight": "regular"
                                                                                },
                                                                                "color": {
                                                                                  "hex": "292D32"
                                                                                },
                                                                                "lineLimit": 2,
                                                                                "multilineAlignment": "center",
                                                                                "textBinding": "offerPerk"
                                                                              }
                                                                            }
                                                                          ]
                                                                        }
                                                                      }
                                                                    ]
                                                                  }
                                                                }
                                                              ]
                                                            }
                                                          },
                                                          {
                                                            "spacer": {}
                                                          }
                                                        ],
                                                        "style": {
                                                          "frame": {
                                                            "maxWidth": "infinity",
                                                            "maxHeight": "infinity"
                                                          },
                                                          "padding": {
                                                            "leading": 12,
                                                            "trailing": 12
                                                          }
                                                        }
                                                      }
                                                    },
                                                    {
                                                      "zStack": {
                                                        "alignment": "center",
                                                        "children": [
                                                          {
                                                            "shape": {
                                                              "type": "roundedRectangle",
                                                              "cornerRadius": 7,
                                                              "fillColor": {
                                                                "binding": {
                                                                  "key": "appDominantColor",
                                                                  "fallback": {
                                                                    "hex": "94348C"
                                                                  }
                                                                }
                                                              },
                                                              "style": {
                                                                "frame": {
                                                                  "width": 20,
                                                                  "height": 20
                                                                }
                                                              }
                                                            }
                                                          },
                                                          {
                                                            "systemImage": {
                                                              "systemName": "checkmark",
                                                              "font": {
                                                                "size": 12,
                                                                "weight": "bold"
                                                              },
                                                              "color": {
                                                                "hex": "FFFFFFFF"
                                                              }
                                                            }
                                                          }
                                                        ],
                                                        "style": {
                                                          "frame": {
                                                            "maxWidth": "infinity",
                                                            "maxHeight": "infinity",
                                                            "alignment": "topTrailing"
                                                          },
                                                          "padding": {
                                                            "top": 16,
                                                            "trailing": 16
                                                          },
                                                          "scrollFade": {
                                                            "centeredOpacity": 1.0,
                                                            "offCenterOpacity": 0.0
                                                          }
                                                        }
                                                      }
                                                    }
                                                  ],
                                                  "style": {
                                                    "frame": {
                                                      "maxWidth": "infinity",
                                                      "maxHeight": "infinity"
                                                    }
                                                  }
                                                }
                                              }
                                            }
                                          }
                                        }
                                      }
                                    ],
                                    "style": {
                                      "scrollTargetLayout": true
                                    }
                                  }
                                },
                                "style": {
                                  "padding": {
                                    "top": 4
                                  }
                                }
                              }
                            },
                            {
                              "conditional": {
                                "condition": {
                                  "hasMultipleOffers": {}
                                },
                                "ifTrue": {
                                  "group": {
                                    "content": {
                                      "compactPageIndicator": {
                                        "activeColor": {
                                          "binding": "selectedOfferDominantColor",
                                          "fallback": {
                                            "hex": "FFCCCCCC"
                                          }
                                        },
                                        "inactiveColor": {
                                          "hex": "FFD8D2D6"
                                        }
                                      }
                                    },
                                    "style": {
                                      "padding": {
                                        "top": 18
                                      }
                                    }
                                  }
                                }
                              }
                            },
                            {
                              "spacer": {}
                            },
                            {
                              "vStack": {
                                "spacing": 12,
                                "alignment": "center",
                                "children": [
                                  {
                                    "text": {
                                      "text": "No charges until trial ends, cancel anytime.",
                                      "font": {
                                        "size": 13,
                                        "weight": "regular"
                                      },
                                      "color": {
                                        "hex": "#6B6B70"
                                      },
                                      "multilineAlignment": "center"
                                    }
                                  },
                                  {
                                    "button": {
                                      "content": {
                                        "text": {
                                          "text": "Activate free ${trialValue} ${trialUnit} of ${appName}",
                                          "font": {
                                            "size": 16,
                                            "weight": "semibold"
                                          },
                                          "color": {
                                            "hex": "#FFFFFF"
                                          },
                                          "multilineAlignment": "center"
                                        }
                                      },
                                      "action": {
                                        "type": "triggerIAP",
                                        "onSuccessState": "congrats"
                                      },
                                      "style": {
                                        "frame": {
                                          "maxWidth": "infinity"
                                        },
                                        "padding": {
                                          "top": 17,
                                          "bottom": 17
                                        },
                                        "cornerRadius": 9999,
                                        "backgroundColor": {
                                          "binding": {
                                            "key": "appDominantColor",
                                            "fallback": {
                                              "hex": "94348C"
                                            }
                                          }
                                        },
                                        "shadow": {
                                          "color": {
                                            "binding": {
                                              "key": "appDominantColor",
                                              "fallback": {
                                                "hex": "94348C"
                                              }
                                            }
                                          },
                                          "radius": 14,
                                          "x": 0,
                                          "y": 6,
                                          "opacity": 0.3
                                        }
                                      }
                                    }
                                  },
                                  {
                                    "button": {
                                      "content": {
                                        "text": {
                                          "text": "No thanks",
                                          "font": {
                                            "size": 16,
                                            "weight": "regular"
                                          },
                                          "color": {
                                            "hex": "#6B6B70"
                                          },
                                          "multilineAlignment": "center"
                                        }
                                      },
                                      "action": "close",
                                      "style": {
                                        "frame": {
                                          "maxWidth": "infinity"
                                        },
                                        "padding": {
                                          "top": 15,
                                          "bottom": 15
                                        },
                                        "cornerRadius": 9999,
                                        "borderWidth": 1,
                                        "borderColor": {
                                          "hex": "#E0DADE"
                                        }
                                      }
                                    }
                                  }
                                ],
                                "style": {
                                  "padding": {
                                    "top": 12,
                                    "leading": 20,
                                    "trailing": 20,
                                    "bottom": 24
                                  },
                                  "frame": {
                                    "maxWidth": "infinity"
                                  }
                                }
                              }
                            }
                          ],
                          "style": {
                            "padding": {
                              "leading": 0,
                              "trailing": 0
                            },
                            "frame": {
                              "maxWidth": "infinity",
                              "maxHeight": "infinity",
                              "alignment": "top"
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            ],
            "style": {
              "safeAreaPadding": true,
              "frame": {
                "maxWidth": "infinity",
                "maxHeight": "infinity",
                "alignment": "top"
              }
            }
          }
        },
        {
          "empty": {}
        }
      ]
    }
  },
  "offerDisplayOrder": [
    2,
    0,
    1
  ],
  "initialSelection": 1,
  "offerLinkPresentation": "external"
}
"""
}
